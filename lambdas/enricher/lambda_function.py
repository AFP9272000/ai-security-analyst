"""
Enricher Lambda for the AI Security Analyst.

Subscribes to the security-findings EventBridge custom bus, normalizes
GuardDuty / Security Hub / custom events into a common schema, and
writes enriched JSON to the enriched-findings S3 bucket where the
`enriched_findings` Glue table can query it.

This is intentionally narrow. Future iterations
will add cross-account Resource Groups Tagging API lookups, Athena
sub-queries for related CloudTrail context, and an inference Lambda
sibling that calls the SageMaker endpoint for anomaly scoring.

Environment variables:
    ENRICHED_BUCKET   Name of the S3 bucket to write to (required)
    ENVIRONMENT       prod | dev (informational; tagged on outputs)
    LOG_LEVEL         INFO | DEBUG | WARNING (default INFO)
"""
from __future__ import annotations

import json
import logging
import os
from datetime import datetime, timezone
from typing import Any

import boto3

# Module-level setup - reused across warm invocations
logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

s3 = boto3.client("s3")

ENRICHED_BUCKET = os.environ["ENRICHED_BUCKET"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "prod")


# Normalization

def normalize_event(event: dict[str, Any]) -> dict[str, Any]:
    """
    Normalize an EventBridge event into the canonical enriched-finding shape.

    Canonical fields (matches Glue table in 04-data/enriched-bucket.tf):
        finding_id, source, detail_type, severity, account_id, region,
        resource_arn, resource_tags, raw_detail, enriched_at
    """
    source = event.get("source", "custom")
    detail_type = event.get("detail-type", "unknown")
    detail = event.get("detail", {}) or {}
    region = event.get("region", "unknown")
    account_id = event.get("account", "unknown")

    finding_id, severity, resource_arn = _extract_source_specific(source, detail)

    return {
        "finding_id": finding_id,
        "source": _source_label(source),
        "detail_type": detail_type,
        "severity": severity,
        "account_id": account_id,
        "region": region,
        "resource_arn": resource_arn,
        "resource_tags": {},  # Reserved for future cross-account enrichment
        "raw_detail": json.dumps(detail),
        "enriched_at": datetime.now(timezone.utc).isoformat(),
    }


def _extract_source_specific(source: str, detail: dict[str, Any]) -> tuple[str, str, str]:
    """Pull finding_id, severity, and resource_arn from a source-specific shape."""
    if source == "aws.guardduty":
        finding_id = detail.get("id", "unknown")
        severity = _guardduty_severity_label(detail.get("severity", 0.0))
        resource_arn = _extract_guardduty_resource(detail)
        return finding_id, severity, resource_arn

    if source == "aws.securityhub":
        findings = detail.get("findings") or [{}]
        first = findings[0] if findings else {}
        finding_id = first.get("Id", "unknown")
        severity = (first.get("Severity") or {}).get("Label", "unknown").lower()
        resources = first.get("Resources") or [{}]
        resource_arn = resources[0].get("Id", "") if resources else ""
        return finding_id, severity, resource_arn

    # Custom / unknown source - best-effort
    finding_id = detail.get("id") or detail.get("finding_id") or "unknown"
    severity = str(detail.get("severity", "unknown"))
    resource_arn = detail.get("resource_arn", "")
    return finding_id, severity, resource_arn


def _source_label(eventbridge_source: str) -> str:
    """Map EventBridge source to the Glue table's enum partition value."""
    mapping = {
        "aws.guardduty": "guardduty",
        "aws.securityhub": "securityhub",
    }
    return mapping.get(eventbridge_source, "custom")


def _guardduty_severity_label(score: float | int) -> str:
    """Map GuardDuty's numeric severity (1.0-8.9) to a categorical label."""
    try:
        s = float(score)
    except (TypeError, ValueError):
        return "unknown"
    if s >= 7.0:
        return "high"
    if s >= 4.0:
        return "medium"
    if s > 0:
        return "low"
    return "informational"


def _extract_guardduty_resource(detail: dict[str, Any]) -> str:
    """Best-effort extraction of resource ARN from a GuardDuty finding."""
    resource = detail.get("resource") or {}
    rtype = resource.get("resourceType", "")
    region = detail.get("region", "")
    acct = detail.get("accountId", "")

    if rtype == "Instance":
        instance_id = (resource.get("instanceDetails") or {}).get("instanceId", "")
        if instance_id:
            return f"arn:aws:ec2:{region}:{acct}:instance/{instance_id}"
    elif rtype == "AccessKey":
        username = (resource.get("accessKeyDetails") or {}).get("userName", "")
        if username:
            return f"arn:aws:iam::{acct}:user/{username}"
    elif rtype == "S3Bucket":
        buckets = resource.get("s3BucketDetails") or [{}]
        if buckets:
            return buckets[0].get("arn", "")

    return ""

# S3 write

def s3_key(finding: dict[str, Any]) -> str:
    """
    Build the S3 object key matching the Glue table's partition layout:
        enriched/<source>/<YYYY>/<MM>/<DD>/<safe_finding_id>.json
    """
    now = datetime.now(timezone.utc)
    source = finding["source"]
    # S3 keys disallow most special characters; sanitize finding IDs
    safe_id = finding["finding_id"].replace("/", "_").replace(":", "_")
    return f"enriched/{source}/{now.year}/{now.month:02d}/{now.day:02d}/{safe_id}.json"


def write_finding(finding: dict[str, Any]) -> str:
    """Serialize and put the finding to S3. Returns the key written."""
    key = s3_key(finding)
    s3.put_object(
        Bucket=ENRICHED_BUCKET,
        Key=key,
        Body=json.dumps(finding, default=str).encode("utf-8"),
        ContentType="application/json",
        ServerSideEncryption="aws:kms",
        Metadata={
            "environment": ENVIRONMENT,
            "source": finding["source"],
        },
    )
    return key


# Handler

def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """
    Lambda entrypoint. Processes ONE EventBridge event per invocation.
    EventBridge's default delivery model is at-least-once, single-event-per-target,
    so we don't iterate over a batch here.
    """
    source = event.get("source", "unknown")
    logger.info("Processing event from source=%s detail-type=%s",
                source, event.get("detail-type", "unknown"))

    try:
        finding = normalize_event(event)
        key = write_finding(finding)
        logger.info("Wrote enriched finding to s3://%s/%s", ENRICHED_BUCKET, key)
        return {"status": "ok", "key": key, "finding_id": finding["finding_id"]}
    except Exception:
        # Re-raise so Lambda surfaces the error to CloudWatch + EventBridge retry
        logger.exception("Failed to process event")
        raise
