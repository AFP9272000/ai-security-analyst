"""
Feature engineering for CloudTrail anomaly detection.

Used by both train.py (during model training) and inference.py (at endpoint
prediction time). The exact same feature transformations must be applied
in both contexts; otherwise the model gets inputs it wasn't trained on.

Input format: pandas DataFrame with CloudTrail event columns. The minimum
required columns are:
    eventtime, eventsource, eventname, sourceipaddress, useridentity,
    errorcode, awsregion

These match the columns exposed by the Glue table in 04-data/glue.tf.

Output: pandas DataFrame with engineered numeric features ready for
IsolationForest. All features are scaled to roughly [0, 1] range
where possible to make the model less sensitive to feature magnitude.
"""
from __future__ import annotations

import json
from datetime import datetime
from typing import Any

import numpy as np
import pandas as pd


# Features the model uses. ORDER MATTERS! this is the contract between
# training and inference. Adding a new feature requires re-training the
# model and bumping the model version.
FEATURE_COLUMNS = [
    "hour_of_day",
    "day_of_week",
    "is_weekend",
    "is_business_hours",
    "is_root_user",
    "is_assumed_role",
    "is_error_response",
    "is_console_action",
    "event_source_rarity",
    "event_name_rarity",
    "region_rarity",
    "ip_octet_variance",
]


def extract_features(df: pd.DataFrame) -> pd.DataFrame:
    """
    Transform raw CloudTrail events into model features.

    The transformations are deliberately STATELESS - no fit_transform
    semantics, no learned encoders. Rarity scores are computed within
    the input batch, which is fine for both training (large batch) and
    inference (single event scored against typical baselines).

    For per-event inference, the rarity features will be computed against
    the single event only and will always be 1.0; this is a known
    limitation that future iterations could address with a precomputed
    rarity lookup table.
    """
    out = pd.DataFrame(index=df.index)

    # Temporal features
    times = pd.to_datetime(df["eventtime"], errors="coerce", utc=True)
    out["hour_of_day"] = times.dt.hour.fillna(12).astype(int) / 24.0
    out["day_of_week"] = times.dt.dayofweek.fillna(3).astype(int) / 7.0
    out["is_weekend"] = (times.dt.dayofweek >= 5).fillna(False).astype(int)
    out["is_business_hours"] = (
        (times.dt.hour >= 8) & (times.dt.hour < 18)
    ).fillna(False).astype(int)

    # Identity-based features
    user_identity = df["useridentity"].apply(_safe_parse_json)
    out["is_root_user"] = user_identity.apply(
        lambda u: int(u.get("type", "").lower() == "root")
    )
    out["is_assumed_role"] = user_identity.apply(
        lambda u: int(u.get("type", "").lower() == "assumedrole")
    )

    # Response status
    out["is_error_response"] = df["errorcode"].notna().astype(int)

    # Console actions (consoleLogin, AssumeRoleWithSAML etc. often differ
    # in patterns from automated calls)
    out["is_console_action"] = df["eventname"].apply(
        lambda name: int(_is_console_event(str(name) if name else ""))
    )

    # Rarity features - frequency of this category in the batch
    out["event_source_rarity"] = _rarity_score(df["eventsource"])
    out["event_name_rarity"] = _rarity_score(df["eventname"])
    out["region_rarity"] = _rarity_score(df["awsregion"])

    # Source IP variance (helps catch traffic from unusual networks)
    out["ip_octet_variance"] = df["sourceipaddress"].apply(_ip_octet_variance)

    return out[FEATURE_COLUMNS].fillna(0.0)


def _safe_parse_json(maybe_json: Any) -> dict:
    """Tolerant JSON parse. Returns empty dict on any parse failure."""
    if isinstance(maybe_json, dict):
        return maybe_json
    if not isinstance(maybe_json, str):
        return {}
    try:
        result = json.loads(maybe_json)
        return result if isinstance(result, dict) else {}
    except (json.JSONDecodeError, ValueError):
        return {}


def _is_console_event(event_name: str) -> bool:
    """Identify console-driven events by name heuristics."""
    console_indicators = ("ConsoleLogin", "SignIn", "Federation", "SwitchRole")
    return any(name in event_name for name in console_indicators)


def _rarity_score(series: pd.Series) -> pd.Series:
    """
    Compute rarity as 1 / frequency-within-batch.
    Common values approach 0, rare values approach 1.
    """
    if series.empty:
        return pd.Series([], dtype=float)
    counts = series.value_counts()
    max_count = counts.max() if len(counts) > 0 else 1
    return series.map(lambda v: 1.0 - (counts.get(v, 0) / max_count))


def _ip_octet_variance(ip_address: Any) -> float:
    """
    Variance across the four octets of an IPv4 address. AWS service
    principal IPs and IPv6 return 0.0. Helps surface unusual private/
    public network mixes.
    """
    if not isinstance(ip_address, str) or "." not in ip_address:
        return 0.0
    try:
        octets = [int(o) for o in ip_address.split(".")]
        if len(octets) != 4:
            return 0.0
        return float(np.var(octets)) / 10000.0  # Normalize roughly to [0, 1]
    except (ValueError, TypeError):
        return 0.0
