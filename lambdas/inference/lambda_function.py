"""
Inference Lambda for the AI Security Analyst.

Triggered by SQS messages from S3 event notifications when the enricher
writes a new enriched finding. Reads the finding from S3, calls the
SageMaker real-time endpoint with extracted CloudTrail-shaped features,
and writes a SCORED finding back to a separate S3 prefix.

Runs IN-VPC (security-tooling private subnets) because SageMaker
endpoints are only reachable via the VPC endpoint for sagemaker.runtime.

Environment variables:
    SCORED_BUCKET        S3 bucket to write scored findings to (same as enriched)
    SAGEMAKER_ENDPOINT   Name of the SageMaker real-time endpoint
    ENVIRONMENT          prod | dev
    LOG_LEVEL            INFO | DEBUG | WARNING (default INFO)

Event shape (from SQS, which received from S3):
    {
        "Records": [
            {
                "body": "<JSON-encoded S3 event>",
                ...
            }
        ]
    }
"""
from __future__ import annotations

import json
import logging
import os
import urllib.parse
from datetime import datetime, timezone
from typing import Any

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

s3 = boto3.client("s3")
sagemaker_runtime = boto3.client("sagemaker-runtime")

SCORED_BUCKET = os.environ["SCORED_BUCKET"]
SAGEMAKER_ENDPOINT = os.environ["SAGEMAKER_ENDPOINT"]
ENVIRONMENT = os.environ.get("ENVIRONMENT", "prod")


# S3 read

def read_enriched_finding(bucket: str, key: str) -> dict[str, Any]:
    """Fetch an enriched finding JSON from S3."""
    logger.debug("Reading s3://%s/%s", bucket, key)
    response = s3.get_object(Bucket=bucket, Key=key)
    body = response["Body"].read().decode("utf-8")
    return json.loads(body)


# SageMaker inference

def extract_features_payload(finding: dict[str, Any]) -> dict[str, Any]:
    """
    Build the SageMaker endpoint payload from an enriched finding.

    The endpoint expects CloudTrail-shaped event records. project the
    finding's raw_detail (which contains the original event data) back
    into the columns the feature engineering module expects.
    """
    raw = finding.get("raw_detail", "{}")
    try:
        detail = json.loads(raw) if isinstance(raw, str) else raw
    except json.JSONDecodeError:
        detail = {}

    # Build a synthetic CloudTrail-like record. The training data has
    # full CloudTrail records; here we're scoring a finding-shaped object.
    # Future iteration: trigger inference on the actual CloudTrail event
    # that generated the finding (looked up via the resource ARN).
    user_identity = detail.get("resource", {}).get("accessKeyDetails", {}).get(
        "userType", "unknown"
    )

    return {
        "events": [{
            "eventtime": finding.get("enriched_at", datetime.now(timezone.utc).isoformat()),
            "eventsource": _eventsource_from_finding(finding),
            "eventname": detail.get("type", "UnknownFinding"),
            "sourceipaddress": _source_ip_from_detail(detail),
            "useridentity": json.dumps({"type": user_identity}),
            "errorcode": None,
            "awsregion": finding.get("region", "unknown"),
        }]
    }


def _eventsource_from_finding(finding: dict[str, Any]) -> str:
    """Map a finding source to a CloudTrail-style eventsource."""
    src = finding.get("source", "custom")
    return {
        "guardduty": "guardduty.amazonaws.com",
        "securityhub": "securityhub.amazonaws.com",
    }.get(src, "custom.amazonaws.com")


def _source_ip_from_detail(detail: dict[str, Any]) -> str:
    """Best-effort source IP extraction from GuardDuty/SecurityHub detail."""
    # GuardDuty: detail.service.action.networkConnectionAction.remoteIpDetails.ipAddressV4
    try:
        return (detail.get("service") or {}).get("action", {}).get(
            "networkConnectionAction", {}).get("remoteIpDetails", {}).get(
            "ipAddressV4", "0.0.0.0")
    except (AttributeError, TypeError):
        return "0.0.0.0"


def score_finding(finding: dict[str, Any]) -> dict[str, Any]:
    """Call the SageMaker endpoint, return the scored finding."""
    payload = extract_features_payload(finding)
    logger.debug("Invoking endpoint=%s payload=%s", SAGEMAKER_ENDPOINT, payload)

    response = sagemaker_runtime.invoke_endpoint(
        EndpointName=SAGEMAKER_ENDPOINT,
        ContentType="application/json",
        Accept="application/json",
        Body=json.dumps(payload).encode("utf-8"),
    )
    result = json.loads(response["Body"].read().decode("utf-8"))
    predictions = result.get("predictions", [])
    first = predictions[0] if predictions else {"score": 0.0, "is_anomaly": False}

    return {
        **finding,
        "anomaly_score": first["score"],
        "is_anomaly": first["is_anomaly"],
        "scored_at": datetime.now(timezone.utc).isoformat(),
        "model_endpoint": SAGEMAKER_ENDPOINT,
    }


# S3 write

def scored_key(finding: dict[str, Any]) -> str:
    """
    Build the S3 key for the scored finding output:
        scored/<source>/<YYYY>/<MM>/<DD>/<safe_finding_id>.json
    """
    now = datetime.now(timezone.utc)
    source = finding.get("source", "custom")
    safe_id = finding.get("finding_id", "unknown").replace("/", "_").replace(":", "_")
    return f"scored/{source}/{now.year}/{now.month:02d}/{now.day:02d}/{safe_id}.json"


def write_scored(finding: dict[str, Any]) -> str:
    """Persist the scored finding back to the same bucket under scored/."""
    key = scored_key(finding)
    s3.put_object(
        Bucket=SCORED_BUCKET,
        Key=key,
        Body=json.dumps(finding, default=str).encode("utf-8"),
        ContentType="application/json",
        ServerSideEncryption="aws:kms",
        Metadata={
            "environment": ENVIRONMENT,
            "source": finding.get("source", "custom"),
            "is_anomaly": str(finding.get("is_anomaly", False)).lower(),
        },
    )
    return key


# Handler

def _parse_s3_event(s3_event_record: dict[str, Any]) -> tuple[str, str]:
    """Pull bucket + key from an S3 event notification record."""
    s3_info = s3_event_record["s3"]
    bucket = s3_info["bucket"]["name"]
    # S3 URL-encodes keys; decode before using
    key = urllib.parse.unquote_plus(s3_info["object"]["key"])
    return bucket, key


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """
    Lambda entrypoint. Processes SQS messages containing S3 event payloads.

    SQS batch size is configurable on the trigger; default is 10. We
    iterate and treat partial batch failures via the standard
    batchItemFailures pattern - so one bad message doesn't kill the rest.
    """
    failures: list[dict[str, str]] = []
    processed = 0

    for record in event.get("Records", []):
        message_id = record.get("messageId", "unknown")
        try:
            # SQS body is a JSON string containing the S3 event
            body = json.loads(record["body"])

            # S3 events have a Records array (multiple objects possible per event)
            for s3_record in body.get("Records", []):
                bucket, key = _parse_s3_event(s3_record)

                # Skip our own scored/ writes to avoid loops
                if key.startswith("scored/"):
                    logger.debug("Skipping scored/ key: %s", key)
                    continue

                logger.info("Processing s3://%s/%s", bucket, key)
                finding = read_enriched_finding(bucket, key)
                scored = score_finding(finding)
                out_key = write_scored(scored)
                logger.info("Wrote scored finding to s3://%s/%s anomaly=%s score=%.4f",
                            SCORED_BUCKET, out_key,
                            scored["is_anomaly"], scored["anomaly_score"])
                processed += 1
        except Exception:
            logger.exception("Failed to process message_id=%s", message_id)
            failures.append({"itemIdentifier": message_id})

    response: dict[str, Any] = {"processed": processed}
    if failures:
        # Standard SQS partial-batch-failure response
        response["batchItemFailures"] = failures
    return response
