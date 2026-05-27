"""
Generate mock CloudTrail-shaped training data and upload to the training bucket.

Usage (from repo root):
    python scripts/generate_mock_training_data.py

What it creates:
    ~1000 synthetic CloudTrail events written as a single parquet file,
    uploaded to s3://ai-sec-analyst-training-data-<acct>/raw/

Why mock data:
    The model only needs to learn "normal" patterns. Real CloudTrail
    history takes weeks to accumulate enough volume. Synthetic data
    with realistic distributions trains a working model immediately
    so i can demonstrate the full pipeline.

    In production, this would be replaced by an Athena export of the
    real CloudTrail table from the log-archive bucket.
"""
from __future__ import annotations

import json
import os
import random
import tempfile
from datetime import datetime, timedelta, timezone
from pathlib import Path

import boto3
import pandas as pd

PROJECT = "ai-sec-analyst"
REGION = os.environ.get("AWS_REGION", "us-east-1")
NUM_RECORDS = 1000
RANDOM_SEED = 42


# Realistic distributions, these mimic CloudTrail patterns from a
# moderately active AWS account
EVENT_SOURCES = [
    "s3.amazonaws.com",
    "ec2.amazonaws.com",
    "iam.amazonaws.com",
    "kms.amazonaws.com",
    "lambda.amazonaws.com",
    "logs.amazonaws.com",
    "sts.amazonaws.com",
    "cloudtrail.amazonaws.com",
]

EVENT_NAMES_BY_SOURCE = {
    "s3.amazonaws.com": ["GetObject", "PutObject", "ListBucket", "HeadObject"],
    "ec2.amazonaws.com": ["DescribeInstances", "DescribeSecurityGroups",
                          "DescribeVpcs", "RunInstances"],
    "iam.amazonaws.com": ["GetUser", "ListRoles", "CreateRole", "AttachRolePolicy"],
    "kms.amazonaws.com": ["Decrypt", "GenerateDataKey", "DescribeKey"],
    "lambda.amazonaws.com": ["Invoke", "GetFunction", "UpdateFunctionCode"],
    "logs.amazonaws.com": ["CreateLogStream", "PutLogEvents", "DescribeLogGroups"],
    "sts.amazonaws.com": ["AssumeRole", "GetCallerIdentity"],
    "cloudtrail.amazonaws.com": ["DescribeTrails", "GetTrailStatus"],
}

REGIONS = ["us-east-1", "us-east-2", "us-west-2"]
USER_TYPES = ["AssumedRole", "IAMUser", "AWSService", "Root"]
USER_TYPE_WEIGHTS = [0.70, 0.20, 0.09, 0.01]  # Root is rare in normal traffic


def random_ip() -> str:
    """Mix of private (mostly) and public IPs - reflects real AWS API traffic."""
    if random.random() < 0.8:
        # Internal/AWS service
        return f"10.0.{random.randint(0, 255)}.{random.randint(1, 254)}"
    else:
        # Public
        return f"{random.randint(1, 223)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"


def generate_event(now: datetime) -> dict:
    """Generate one synthetic CloudTrail event."""
    # Time within the last 7 days, weighted toward business hours
    hours_back = random.randint(0, 7 * 24)
    event_time = now - timedelta(hours=hours_back)
    if 8 <= event_time.hour < 18 and event_time.weekday() < 5:
        # Business hours - more activity
        pass
    elif random.random() < 0.7:
        # 70% of off-hours events get re-rolled into business hours
        event_time = event_time.replace(hour=random.randint(8, 17))

    source = random.choice(EVENT_SOURCES)
    name = random.choice(EVENT_NAMES_BY_SOURCE[source])
    user_type = random.choices(USER_TYPES, weights=USER_TYPE_WEIGHTS)[0]
    region = random.choice(REGIONS)

    # 5% of events have errors
    error_code = "AccessDenied" if random.random() < 0.05 else None

    return {
        "eventtime": event_time.isoformat() + "Z",
        "eventsource": source,
        "eventname": name,
        "sourceipaddress": random_ip(),
        "useridentity": json.dumps({
            "type": user_type,
            "arn": f"arn:aws:iam::287127677567:{'role' if user_type == 'AssumedRole' else 'user'}/example",
        }),
        "errorcode": error_code,
        "awsregion": region,
    }


def main():
    random.seed(RANDOM_SEED)

    print(f"Generating {NUM_RECORDS} synthetic CloudTrail events...")
    now = datetime.now(timezone.utc)
    records = [generate_event(now) for _ in range(NUM_RECORDS)]
    df = pd.DataFrame(records)
    print(f"  Source distribution: {df['eventsource'].value_counts().to_dict()}")
    print(f"  Event count: {len(df)}")

    # Resolve account ID and bucket name
    sts = boto3.client("sts")
    account_id = sts.get_caller_identity()["Account"]
    bucket = f"{PROJECT}-training-data-{account_id}"
    key = "raw/cloudtrail-mock.parquet"

    # Write parquet to temp file, upload
    with tempfile.TemporaryDirectory() as tmpdir:
        tmppath = Path(tmpdir) / "cloudtrail-mock.parquet"
        df.to_parquet(tmppath, index=False)
        size_kb = tmppath.stat().st_size / 1024
        print(f"  Parquet size: {size_kb:.1f} KB")

        s3 = boto3.client("s3", region_name=REGION)
        print(f"Uploading to s3://{bucket}/{key}...")
        s3.upload_file(str(tmppath), bucket, key)

    print(f"Done. Training data at s3://{bucket}/{key}")
    print("Next: python scripts/run_pipeline.py register && python scripts/run_pipeline.py execute")


if __name__ == "__main__":
    main()
