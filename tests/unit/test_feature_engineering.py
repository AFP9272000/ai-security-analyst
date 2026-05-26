"""
Unit tests for the feature engineering module.

Run from repo root:
    python -m pytest tests/unit/test_feature_engineering.py -v
"""
from __future__ import annotations

import sys
from pathlib import Path

import pandas as pd
import pytest

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "containers" / "anomaly-model"))

from feature_engineering import FEATURE_COLUMNS, extract_features  # noqa: E402


@pytest.fixture
def sample_cloudtrail_df() -> pd.DataFrame:
    """A small but realistic CloudTrail batch."""
    return pd.DataFrame([
        {
            "eventtime": "2026-05-23T14:30:00Z",
            "eventsource": "s3.amazonaws.com",
            "eventname": "GetObject",
            "sourceipaddress": "10.0.1.42",
            "useridentity": '{"type": "AssumedRole", "arn": "arn:aws:iam::123:role/x"}',
            "errorcode": None,
            "awsregion": "us-east-1",
        },
        {
            "eventtime": "2026-05-23T03:15:00Z",  # 3am - off hours
            "eventsource": "iam.amazonaws.com",
            "eventname": "ConsoleLogin",
            "sourceipaddress": "203.0.113.50",
            "useridentity": '{"type": "Root"}',
            "errorcode": None,
            "awsregion": "us-east-1",
        },
        {
            "eventtime": "2026-05-23T14:31:00Z",
            "eventsource": "ec2.amazonaws.com",
            "eventname": "DescribeInstances",
            "sourceipaddress": "10.0.1.42",
            "useridentity": '{"type": "AssumedRole"}',
            "errorcode": "AccessDenied",
            "awsregion": "us-east-2",
        },
    ])


def test_feature_columns_present(sample_cloudtrail_df):
    """All expected feature columns are produced, in order."""
    result = extract_features(sample_cloudtrail_df)
    assert list(result.columns) == FEATURE_COLUMNS


def test_temporal_features(sample_cloudtrail_df):
    """Hour of day and weekend flags work."""
    result = extract_features(sample_cloudtrail_df)
    # Row 0: 14:30 UTC -> hour_of_day ~ 14/24
    assert 0.55 < result.iloc[0]["hour_of_day"] < 0.60
    # Row 1: 03:15 -> early morning, not business hours
    assert result.iloc[1]["is_business_hours"] == 0
    # Row 0: business hours
    assert result.iloc[0]["is_business_hours"] == 1


def test_identity_features(sample_cloudtrail_df):
    """Root vs assumed-role detection."""
    result = extract_features(sample_cloudtrail_df)
    # Row 0 & 2 are AssumedRole; row 1 is Root
    assert result.iloc[0]["is_assumed_role"] == 1
    assert result.iloc[0]["is_root_user"] == 0
    assert result.iloc[1]["is_root_user"] == 1
    assert result.iloc[1]["is_assumed_role"] == 0


def test_error_flag(sample_cloudtrail_df):
    """Error code presence flagged correctly."""
    result = extract_features(sample_cloudtrail_df)
    assert result.iloc[0]["is_error_response"] == 0
    assert result.iloc[2]["is_error_response"] == 1


def test_console_action_detection(sample_cloudtrail_df):
    """ConsoleLogin recognized as console action."""
    result = extract_features(sample_cloudtrail_df)
    assert result.iloc[1]["is_console_action"] == 1
    assert result.iloc[0]["is_console_action"] == 0


def test_empty_input_returns_empty_features():
    """Empty input does not crash."""
    empty_df = pd.DataFrame(columns=[
        "eventtime", "eventsource", "eventname", "sourceipaddress",
        "useridentity", "errorcode", "awsregion"
    ])
    result = extract_features(empty_df)
    assert result.empty
    assert list(result.columns) == FEATURE_COLUMNS


def test_missing_columns_filled_with_zero():
    """Missing or null values don't crash; produce 0 features."""
    df = pd.DataFrame([{
        "eventtime": None,
        "eventsource": None,
        "eventname": None,
        "sourceipaddress": None,
        "useridentity": None,
        "errorcode": None,
        "awsregion": None,
    }])
    result = extract_features(df)
    # Should not crash; all rarity/flag features default to 0
    assert len(result) == 1


def test_malformed_useridentity_does_not_crash():
    """Useridentity that isn't valid JSON returns empty dict, doesn't crash."""
    df = pd.DataFrame([{
        "eventtime": "2026-05-23T14:00:00Z",
        "eventsource": "s3.amazonaws.com",
        "eventname": "GetObject",
        "sourceipaddress": "10.0.0.1",
        "useridentity": "{not valid json}",
        "errorcode": None,
        "awsregion": "us-east-1",
    }])
    result = extract_features(df)
    assert result.iloc[0]["is_root_user"] == 0
    assert result.iloc[0]["is_assumed_role"] == 0


def test_ipv6_address_handled():
    """IPv6 addresses don't crash the octet variance calculation."""
    df = pd.DataFrame([{
        "eventtime": "2026-05-23T14:00:00Z",
        "eventsource": "s3.amazonaws.com",
        "eventname": "GetObject",
        "sourceipaddress": "2001:db8::1",
        "useridentity": "{}",
        "errorcode": None,
        "awsregion": "us-east-1",
    }])
    result = extract_features(df)
    assert result.iloc[0]["ip_octet_variance"] == 0.0
