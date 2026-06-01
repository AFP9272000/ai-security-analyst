"""
Unit tests for the Athena query tool's query builder.

The build_query function is the security-critical piece (it constructs
SQL), so it gets thorough coverage of the allowlist + casting behavior.

Run from repo root:
    python -m pytest tests/unit/test_athena_tool.py -v
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "lambdas" / "agent-tools" / "athena_query"))

os.environ.setdefault("GLUE_DATABASE", "ai_sec_analyst_security")
os.environ.setdefault("ATHENA_WORKGROUP", "ai-sec-analyst-security")

import lambda_function as tool  # noqa: E402


def test_query_with_no_filters_is_valid():
    sql = tool.build_query()
    assert "FROM ai_sec_analyst_security.scored_findings" in sql
    assert "ORDER BY anomaly_score ASC" in sql
    assert "LIMIT 25" in sql
    # Default 7-day window applied
    assert "interval '7' day" in sql


def test_severity_filter_allowed():
    sql = tool.build_query(severity="high")
    assert "severity = 'high'" in sql


def test_severity_filter_case_insensitive():
    sql = tool.build_query(severity="HIGH")
    assert "severity = 'high'" in sql


def test_invalid_severity_rejected():
    with pytest.raises(ValueError, match="invalid severity"):
        tool.build_query(severity="critical")  # not in allowlist


def test_sql_injection_in_severity_rejected():
    # The whole point: a malicious value is rejected, never interpolated
    with pytest.raises(ValueError):
        tool.build_query(severity="high' OR '1'='1")


def test_source_filter_allowed():
    sql = tool.build_query(source="guardduty")
    assert "source = 'guardduty'" in sql


def test_invalid_source_rejected():
    with pytest.raises(ValueError, match="invalid source"):
        tool.build_query(source="'; DROP TABLE findings; --")


def test_only_anomalies_true_variants():
    for val in (True, "true", "True", "1", "yes"):
        sql = tool.build_query(only_anomalies=val)
        assert "is_anomaly = true" in sql


def test_only_anomalies_false_omits_clause():
    sql = tool.build_query(only_anomalies=False)
    assert "is_anomaly = true" not in sql


def test_days_back_cast_to_int():
    sql = tool.build_query(days_back="30")
    assert "interval '30' day" in sql


def test_days_back_garbage_falls_back_to_default():
    sql = tool.build_query(days_back="not-a-number")
    assert "interval '7' day" in sql


def test_limit_capped_at_max():
    sql = tool.build_query(limit=9999)
    assert f"LIMIT {tool.MAX_LIMIT}" in sql


def test_limit_garbage_falls_back():
    sql = tool.build_query(limit="abc")
    assert "LIMIT 25" in sql


def test_combined_filters():
    sql = tool.build_query(severity="high", source="guardduty", days_back=14, only_anomalies=True, limit=10)
    assert "severity = 'high'" in sql
    assert "source = 'guardduty'" in sql
    assert "interval '14' day" in sql
    assert "is_anomaly = true" in sql
    assert "LIMIT 10" in sql


def test_response_envelope_shape():
    event = {"actionGroup": "ag", "function": "query_security_findings", "parameters": []}
    resp = tool._respond(event, "hello")
    assert resp["messageVersion"] == "1.0"
    assert resp["response"]["function"] == "query_security_findings"
    assert resp["response"]["functionResponse"]["responseBody"]["TEXT"]["body"] == "hello"
