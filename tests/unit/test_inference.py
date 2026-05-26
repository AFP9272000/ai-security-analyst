"""
Unit tests for the inference Lambda.

Run from repo root:
    python -m pytest tests/unit/test_inference.py -v
"""
from __future__ import annotations

import io
import json
import os
import sys
from pathlib import Path
from unittest.mock import MagicMock

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

os.environ.setdefault("SCORED_BUCKET", "test-bucket")
os.environ.setdefault("SAGEMAKER_ENDPOINT", "test-endpoint")

from lambdas.inference import lambda_function as inference  # noqa: E402


# Fixtures

@pytest.fixture
def enriched_finding() -> dict:
    """An enriched finding as written by the enricher Lambda."""
    return {
        "finding_id": "gd-finding-abc123",
        "source": "guardduty",
        "detail_type": "GuardDuty Finding",
        "severity": "high",
        "account_id": "287127677567",
        "region": "us-east-1",
        "resource_arn": "arn:aws:ec2:us-east-1:287127677567:instance/i-1234",
        "resource_tags": {},
        "raw_detail": json.dumps({
            "id": "gd-finding-abc123",
            "type": "UnauthorizedAccess:EC2/SSHBruteForce",
            "severity": 7.5,
            "service": {
                "action": {
                    "networkConnectionAction": {
                        "remoteIpDetails": {"ipAddressV4": "203.0.113.50"}
                    }
                }
            },
            "resource": {
                "accessKeyDetails": {"userType": "AssumedRole"}
            },
        }),
        "enriched_at": "2026-05-23T14:30:00+00:00",
    }


@pytest.fixture
def sqs_event(enriched_finding) -> dict:
    """SQS message containing an S3 event for the enriched finding."""
    s3_event = {
        "Records": [{
            "s3": {
                "bucket": {"name": "ai-sec-analyst-enriched-findings-834251004218"},
                "object": {"key": "enriched/guardduty/2026/05/23/gd-finding-abc123.json"},
            }
        }]
    }
    return {
        "Records": [{
            "messageId": "test-msg-1",
            "body": json.dumps(s3_event),
        }]
    }


# Feature payload extraction

def test_extract_features_payload_shape(enriched_finding):
    payload = inference.extract_features_payload(enriched_finding)
    assert "events" in payload
    assert len(payload["events"]) == 1
    event = payload["events"][0]
    for field in ["eventtime", "eventsource", "eventname", "sourceipaddress",
                  "useridentity", "errorcode", "awsregion"]:
        assert field in event


def test_extract_features_pulls_guardduty_source_ip(enriched_finding):
    payload = inference.extract_features_payload(enriched_finding)
    assert payload["events"][0]["sourceipaddress"] == "203.0.113.50"


def test_extract_features_maps_source_to_eventsource(enriched_finding):
    payload = inference.extract_features_payload(enriched_finding)
    assert payload["events"][0]["eventsource"] == "guardduty.amazonaws.com"


def test_extract_features_handles_missing_raw_detail():
    finding = {
        "finding_id": "x",
        "source": "custom",
        "raw_detail": "not valid json",
        "region": "us-east-1",
    }
    payload = inference.extract_features_payload(finding)
    # Falls back gracefully
    assert payload["events"][0]["sourceipaddress"] == "0.0.0.0"


# S3 key generation

def test_scored_key_layout():
    finding = {"finding_id": "abc/123:def", "source": "guardduty"}
    key = inference.scored_key(finding)
    parts = key.split("/")
    assert parts[0] == "scored"
    assert parts[1] == "guardduty"
    assert len(parts[2]) == 4  # year
    assert parts[5].endswith(".json")
    # Sanitization applied
    assert ":" not in parts[5]


# Handler

def test_handler_full_path(enriched_finding, sqs_event, monkeypatch):
    """End-to-end: SQS -> S3 read -> endpoint call -> S3 write."""
    # Mock S3 get_object
    def fake_get_object(Bucket, Key):
        return {"Body": io.BytesIO(json.dumps(enriched_finding).encode("utf-8"))}

    # Mock SageMaker invoke_endpoint
    def fake_invoke(EndpointName, ContentType, Accept, Body):
        return {"Body": io.BytesIO(json.dumps({
            "predictions": [{"score": -0.234, "is_anomaly": True}]
        }).encode("utf-8"))}

    put_captured = {}

    def fake_put_object(**kwargs):
        put_captured.update(kwargs)
        return {}

    monkeypatch.setattr(inference.s3, "get_object", fake_get_object)
    monkeypatch.setattr(inference.sagemaker_runtime, "invoke_endpoint", fake_invoke)
    monkeypatch.setattr(inference.s3, "put_object", fake_put_object)

    result = inference.handler(sqs_event, None)

    assert result["processed"] == 1
    assert "batchItemFailures" not in result
    assert put_captured["Bucket"] == "test-bucket"
    assert put_captured["Key"].startswith("scored/guardduty/")

    written = json.loads(put_captured["Body"].decode("utf-8"))
    assert written["finding_id"] == "gd-finding-abc123"
    assert written["is_anomaly"] is True
    assert written["anomaly_score"] == -0.234
    assert "scored_at" in written


def test_handler_skips_scored_prefix_to_prevent_loops(enriched_finding, monkeypatch):
    """Lambda must skip its own scored/ writes."""
    sqs_event = {
        "Records": [{
            "messageId": "test-loop",
            "body": json.dumps({
                "Records": [{
                    "s3": {
                        "bucket": {"name": "test-bucket"},
                        "object": {"key": "scored/guardduty/2026/05/23/x.json"},
                    }
                }]
            }),
        }]
    }

    get_called = MagicMock()
    monkeypatch.setattr(inference.s3, "get_object", get_called)

    result = inference.handler(sqs_event, None)

    assert result["processed"] == 0
    get_called.assert_not_called()


def test_handler_partial_failure_returns_batchitemfailures(enriched_finding, monkeypatch):
    """One failing message doesn't kill the batch; failures returned for SQS retry."""
    def flaky_get_object(Bucket, Key):
        if "fails" in Key:
            raise RuntimeError("S3 unavailable")
        return {"Body": io.BytesIO(json.dumps(enriched_finding).encode("utf-8"))}

    def fake_invoke(**kwargs):
        return {"Body": io.BytesIO(json.dumps({
            "predictions": [{"score": 0.1, "is_anomaly": False}]
        }).encode("utf-8"))}

    monkeypatch.setattr(inference.s3, "get_object", flaky_get_object)
    monkeypatch.setattr(inference.sagemaker_runtime, "invoke_endpoint", fake_invoke)
    monkeypatch.setattr(inference.s3, "put_object", lambda **kwargs: {})

    event = {
        "Records": [
            {
                "messageId": "msg-good",
                "body": json.dumps({"Records": [{
                    "s3": {
                        "bucket": {"name": "test-bucket"},
                        "object": {"key": "enriched/guardduty/2026/05/23/good.json"},
                    }
                }]}),
            },
            {
                "messageId": "msg-bad",
                "body": json.dumps({"Records": [{
                    "s3": {
                        "bucket": {"name": "test-bucket"},
                        "object": {"key": "enriched/guardduty/2026/05/23/fails.json"},
                    }
                }]}),
            },
        ]
    }

    result = inference.handler(event, None)
    assert result["processed"] == 1
    assert result["batchItemFailures"] == [{"itemIdentifier": "msg-bad"}]
