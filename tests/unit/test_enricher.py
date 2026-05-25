"""
Unit tests for the enricher Lambda.

These tests cover the pure normalization logic. They do NOT call AWS;
the boto3 S3 client is replaced with a stub via monkeypatch where needed.

Run from repo root:
    python -m pytest tests/unit/test_enricher.py -v
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import pytest

# Ensure the lambda code is importable
REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

# Required env var must be set before import
os.environ.setdefault("ENRICHED_BUCKET", "test-bucket")

from lambdas.enricher import lambda_function as enricher  # noqa: E402

# Fixtures

@pytest.fixture
def guardduty_event() -> dict:
    """Canonical-ish GuardDuty finding shape from EventBridge."""
    return {
        "version": "0",
        "id": "eventbridge-event-id",
        "detail-type": "GuardDuty Finding",
        "source": "aws.guardduty",
        "account": "287127677567",
        "time": "2026-05-23T20:00:00Z",
        "region": "us-east-1",
        "detail": {
            "id": "gd-finding-abc123",
            "type": "UnauthorizedAccess:EC2/SSHBruteForce",
            "severity": 7.5,
            "accountId": "287127677567",
            "region": "us-east-1",
            "resource": {
                "resourceType": "Instance",
                "instanceDetails": {
                    "instanceId": "i-0123456789abcdef0",
                    "instanceType": "t3.micro",
                },
            },
        },
    }


@pytest.fixture
def securityhub_event() -> dict:
    return {
        "version": "0",
        "id": "eventbridge-event-id",
        "detail-type": "Security Hub Findings - Imported",
        "source": "aws.securityhub",
        "account": "287127677567",
        "region": "us-east-1",
        "detail": {
            "findings": [
                {
                    "Id": "sh-finding-xyz789",
                    "Severity": {"Label": "MEDIUM", "Normalized": 40},
                    "Resources": [
                        {
                            "Type": "AwsS3Bucket",
                            "Id": "arn:aws:s3:::my-test-bucket",
                        }
                    ],
                }
            ]
        },
    }


@pytest.fixture
def custom_event() -> dict:
    return {
        "source": "custom.test",
        "detail-type": "ManualTest",
        "account": "834251004218",
        "region": "us-east-1",
        "detail": {"id": "custom-1", "severity": "low"},
    }

# Normalization tests

def test_normalize_guardduty_high_severity(guardduty_event):
    result = enricher.normalize_event(guardduty_event)
    assert result["source"] == "guardduty"
    assert result["finding_id"] == "gd-finding-abc123"
    assert result["severity"] == "high"
    assert result["account_id"] == "287127677567"
    assert result["region"] == "us-east-1"
    assert "i-0123456789abcdef0" in result["resource_arn"]
    assert result["detail_type"] == "GuardDuty Finding"
    assert "resource_tags" in result and result["resource_tags"] == {}
    assert "enriched_at" in result


def test_normalize_guardduty_severity_buckets():
    base = {"source": "aws.guardduty", "detail": {"id": "x", "severity": None}}

    def with_severity(s):
        e = {**base, "detail": {**base["detail"], "severity": s}}
        return enricher.normalize_event(e)["severity"]

    assert with_severity(8.5) == "high"
    assert with_severity(7.0) == "high"
    assert with_severity(5.0) == "medium"
    assert with_severity(4.0) == "medium"
    assert with_severity(2.0) == "low"
    assert with_severity(0) == "informational"


def test_normalize_securityhub(securityhub_event):
    result = enricher.normalize_event(securityhub_event)
    assert result["source"] == "securityhub"
    assert result["finding_id"] == "sh-finding-xyz789"
    assert result["severity"] == "medium"
    assert result["resource_arn"] == "arn:aws:s3:::my-test-bucket"


def test_normalize_custom_event(custom_event):
    result = enricher.normalize_event(custom_event)
    assert result["source"] == "custom"
    assert result["finding_id"] == "custom-1"
    assert result["severity"] == "low"


def test_normalize_missing_detail_does_not_crash():
    result = enricher.normalize_event({"source": "aws.guardduty"})
    assert result["finding_id"] == "unknown"
    assert result["source"] == "guardduty"


def test_normalize_malformed_severity():
    event = {"source": "aws.guardduty", "detail": {"id": "x", "severity": "not-a-number"}}
    result = enricher.normalize_event(event)
    assert result["severity"] == "unknown"


# S3 key generation

def test_s3_key_layout_matches_glue_partitions():
    finding = {
        "finding_id": "abc/123:def",
        "source": "guardduty",
    }
    key = enricher.s3_key(finding)
    # Special characters in finding_id sanitized
    assert "/" not in key.split("/")[-1].replace(".json", "").split("_")[0]
    # Path layout matches `enriched/<source>/<YYYY>/<MM>/<DD>/<id>.json`
    parts = key.split("/")
    assert parts[0] == "enriched"
    assert parts[1] == "guardduty"
    assert len(parts[2]) == 4  # year
    assert len(parts[3]) == 2  # month
    assert len(parts[4]) == 2  # day
    assert parts[5].endswith(".json")


# Handler wiring 

def test_handler_writes_to_s3(guardduty_event, monkeypatch):
    captured = {}

    def fake_put_object(**kwargs):
        captured.update(kwargs)
        return {}

    monkeypatch.setattr(enricher.s3, "put_object", fake_put_object)

    result = enricher.handler(guardduty_event, None)

    assert result["status"] == "ok"
    assert captured["Bucket"] == "test-bucket"
    assert captured["Key"].startswith("enriched/guardduty/")
    assert captured["ServerSideEncryption"] == "aws:kms"

    # Verify the body is valid JSON with the expected shape
    body = json.loads(captured["Body"].decode("utf-8"))
    assert body["finding_id"] == "gd-finding-abc123"
    assert body["severity"] == "high"


def test_handler_propagates_s3_errors(guardduty_event, monkeypatch):
    def failing_put_object(**kwargs):
        raise RuntimeError("simulated S3 failure")

    monkeypatch.setattr(enricher.s3, "put_object", failing_put_object)

    with pytest.raises(RuntimeError, match="simulated S3 failure"):
        enricher.handler(guardduty_event, None)
