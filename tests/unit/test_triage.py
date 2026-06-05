"""
Unit tests for the triage Lambda's pure helpers: parse_finding (both
event schemas) and format_alert. The agent-invoke and SNS paths are
exercised by the deployed end-to-end test in the README.

Run from repo root:
    python -m pytest tests/unit/test_triage.py -v
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "lambdas" / "triage"))

os.environ.setdefault("SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:111111111111:test")
os.environ.setdefault("AGENT_ID", "TESTAGENT")

import lambda_function as triage  # noqa: E402


# GuardDuty schema

def _guardduty_event():
    return {
        "source": "aws.guardduty",
        "account": "287127677567",
        "region": "us-east-1",
        "detail": {
            "id": "gd-abc123",
            "type": "UnauthorizedAccess:EC2/SSHBruteForce",
            "severity": 8,
            "accountId": "287127677567",
            "region": "us-east-1",
            "description": "EC2 instance is being brute-forced over SSH.",
            "resource": {"resourceType": "Instance"},
        },
    }


def test_parse_guardduty_core_fields():
    f = triage.parse_finding(_guardduty_event())
    assert f["kind"] == "GuardDuty"
    assert f["id"] == "gd-abc123"
    assert f["severity"] == 8
    assert f["account"] == "287127677567"
    assert f["resource"] == "Instance"
    assert "brute-forced" in f["description"]


def test_parse_guardduty_falls_back_to_top_level_account():
    ev = _guardduty_event()
    del ev["detail"]["accountId"]
    f = triage.parse_finding(ev)
    assert f["account"] == "287127677567"  # from top-level event.account


# Security Hub schema

def _securityhub_event():
    return {
        "source": "aws.securityhub",
        "account": "834251004218",
        "region": "us-east-1",
        "detail": {
            "findings": [{
                "Id": "sh-xyz789",
                "Title": "S3 bucket should block public access",
                "Severity": {"Label": "HIGH"},
                "AwsAccountId": "834251004218",
                "Region": "us-west-2",
                "Description": "A bucket allows public access.",
                "Resources": [{"Type": "AwsS3Bucket"}],
            }]
        },
    }


def test_parse_securityhub_core_fields():
    f = triage.parse_finding(_securityhub_event())
    assert f["kind"] == "SecurityHub"
    assert f["id"] == "sh-xyz789"
    assert f["severity"] == "HIGH"
    assert f["account"] == "834251004218"
    assert f["region"] == "us-west-2"  # finding region wins over event region
    assert f["resource"] == "AwsS3Bucket"


def test_parse_securityhub_empty_findings():
    ev = {"source": "aws.securityhub", "account": "1", "region": "us-east-1", "detail": {"findings": []}}
    f = triage.parse_finding(ev)
    assert f["kind"] == "SecurityHub"
    assert f["id"] == "unknown"


# Unknown / direct-invoke

def test_parse_unknown_source_passthrough():
    f = triage.parse_finding({"detail": {"id": "x1", "title": "manual test"}})
    assert f["id"] == "x1"
    assert f["title"] == "manual test"


# format_alert

def test_format_alert_includes_core_fields_and_triage():
    f = triage.parse_finding(_guardduty_event())
    subject, body = triage.format_alert(f, "Risk is high. 1) isolate. 2) patch.")
    assert subject.startswith("[8] GuardDuty finding in account 287127677567")
    assert "gd-abc123" in body
    assert "AI analyst triage" in body
    assert "isolate" in body


def test_format_alert_without_triage_notes_absence():
    f = triage.parse_finding(_securityhub_event())
    subject, body = triage.format_alert(f, None)
    assert "not attached" in body
    assert "AI analyst triage" not in body


def test_format_alert_subject_capped_at_100():
    f = triage.parse_finding(_guardduty_event())
    f["account"] = "x" * 200
    subject, _ = triage.format_alert(f, None)
    assert len(subject) <= 100
    assert subject.endswith("...")
