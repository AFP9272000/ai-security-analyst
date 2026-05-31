"""
Seed the Knowledge Base with realistic findings.

Generates synthetic-but-plausible security findings in the SAME schema
the enricher and inference Lambdas produce, and writes them to the
enriched/ and scored/ prefixes of the enriched-findings bucket. The
Bedrock Knowledge Base then ingests them on its next sync.

This decouples KB population from the SageMaker endpoint: you don't have
to stand up the (~$50/mo) endpoint just to have data for the agent to
reason over. The scored findings here carry synthetic anomaly scores in
the same shape the inference Lambda would produce.

Usage (from repo root):
    $env:AWS_PROFILE = "security-tooling"
    python scripts/generate_seed_findings.py --count 60

    # write locally without uploading, to inspect first:
    python scripts/generate_seed_findings.py --count 5 --dry-run
"""
from __future__ import annotations

import argparse
import json
import random
import uuid
from datetime import datetime, timedelta, timezone

import boto3

# --- finding building blocks -------------------------------------------------

ACCOUNTS = {
    "management": "724772086149",
    "log-archive": "008714537009",
    "security-tooling": "834251004218",
    "workload": "287127677567",
}

REGIONS = ["us-east-1", "us-east-2", "us-west-2"]

GUARDDUTY_TYPES = [
    ("UnauthorizedAccess:EC2/SSHBruteForce", "high", "Instance"),
    ("UnauthorizedAccess:IAMUser/ConsoleLoginSuccess.B", "medium", "AccessKey"),
    ("Recon:EC2/PortProbeUnprotectedPort", "low", "Instance"),
    ("CryptoCurrency:EC2/BitcoinTool.B!DNS", "high", "Instance"),
    ("Exfiltration:S3/ObjectRead.Unusual", "high", "S3Bucket"),
    ("Policy:S3/BucketBlockPublicAccessDisabled", "medium", "S3Bucket"),
    ("PrivilegeEscalation:IAMUser/AdministrativePermissions", "high", "AccessKey"),
    ("Discovery:S3/MaliciousIPCaller", "medium", "S3Bucket"),
]

SECURITYHUB_TYPES = [
    ("Software and Configuration Checks/AWS Security Best Practices", "medium", "AwsS3Bucket"),
    ("Effects/Data Exposure/S3 bucket publicly readable", "high", "AwsS3Bucket"),
    ("Software and Configuration Checks/Vulnerabilities/CVE", "high", "AwsEc2Instance"),
    ("Unusual Behaviors/IAM root user activity", "high", "AwsIamUser"),
]


def _ts_within_days(days: int) -> str:
    dt = datetime.now(timezone.utc) - timedelta(
        hours=random.randint(0, days * 24),
        minutes=random.randint(0, 59),
    )
    return dt.isoformat()


def _random_ip(external: bool) -> str:
    if external:
        return f"{random.randint(11, 223)}.{random.randint(0,255)}.{random.randint(0,255)}.{random.randint(1,254)}"
    return f"10.0.{random.randint(0,255)}.{random.randint(1,254)}"


def make_guardduty_enriched() -> dict:
    gtype, severity, rtype = random.choice(GUARDDUTY_TYPES)
    acct = random.choice(list(ACCOUNTS.values()))
    region = random.choice(REGIONS)
    fid = f"gd-{uuid.uuid4().hex[:16]}"
    external = severity in ("high", "medium")

    raw_detail = {
        "id": fid,
        "type": gtype,
        "severity": {"high": 7.8, "medium": 5.2, "low": 2.4}[severity],
        "accountId": acct,
        "region": region,
        "resource": {"resourceType": rtype},
        "service": {
            "action": {
                "networkConnectionAction": {
                    "remoteIpDetails": {"ipAddressV4": _random_ip(external)}
                }
            }
        },
    }

    return {
        "finding_id": fid,
        "source": "guardduty",
        "detail_type": "GuardDuty Finding",
        "severity": severity,
        "account_id": acct,
        "region": region,
        "resource_arn": f"arn:aws:ec2:{region}:{acct}:instance/i-{uuid.uuid4().hex[:17]}",
        "resource_tags": {},
        "raw_detail": json.dumps(raw_detail),
        "enriched_at": _ts_within_days(7),
    }


def make_securityhub_enriched() -> dict:
    stype, severity, rtype = random.choice(SECURITYHUB_TYPES)
    acct = random.choice(list(ACCOUNTS.values()))
    region = random.choice(REGIONS)
    fid = f"sh-{uuid.uuid4().hex[:16]}"

    raw_detail = {
        "findings": [{
            "Id": fid,
            "Title": stype,
            "Severity": {"Label": severity.upper()},
            "Resources": [{"Type": rtype, "Id": f"arn:aws:s3:::{uuid.uuid4().hex[:12]}-bucket"}],
        }]
    }

    return {
        "finding_id": fid,
        "source": "securityhub",
        "detail_type": "Security Hub Findings - Imported",
        "severity": severity,
        "account_id": acct,
        "region": region,
        "resource_arn": f"arn:aws:s3:::{uuid.uuid4().hex[:12]}-bucket",
        "resource_tags": {},
        "raw_detail": json.dumps(raw_detail),
        "enriched_at": _ts_within_days(7),
    }


def to_scored(enriched: dict) -> dict:
    """Add the fields the inference Lambda would add, with a synthetic score."""
    # Bias anomaly toward high-severity findings, with noise
    base = {"high": 0.7, "medium": 0.35, "low": 0.1}[enriched["severity"]]
    is_anomaly = random.random() < base
    # decision_function: lower = more anomalous
    score = round(random.uniform(-0.35, -0.02) if is_anomaly else random.uniform(0.02, 0.4), 4)
    return {
        **enriched,
        "anomaly_score": score,
        "is_anomaly": is_anomaly,
        "scored_at": _ts_within_days(7),
        "model_endpoint": "ai-sec-analyst-anomaly-endpoint",
    }


def s3_key(prefix: str, finding: dict) -> str:
    dt = datetime.fromisoformat(finding["enriched_at"])
    safe = finding["finding_id"].replace("/", "_").replace(":", "_")
    return f"{prefix}/{finding['source']}/{dt.year}/{dt.month:02d}/{dt.day:02d}/{safe}.json"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--count", type=int, default=60, help="Number of findings to generate")
    parser.add_argument("--bucket", default=f"ai-sec-analyst-enriched-findings-{ACCOUNTS['security-tooling']}")
    parser.add_argument("--dry-run", action="store_true", help="Write to ./seed-output/ instead of S3")
    args = parser.parse_args()

    findings = []
    for _ in range(args.count):
        if random.random() < 0.65:
            findings.append(make_guardduty_enriched())
        else:
            findings.append(make_securityhub_enriched())

    if args.dry_run:
        import os
        os.makedirs("seed-output", exist_ok=True)
        for f in findings[:5]:
            scored = to_scored(f)
            print(f"--- enriched: {s3_key('enriched', f)} ---")
            print(json.dumps(f, indent=2)[:400])
            print(f"--- scored:   {s3_key('scored', scored)} ---")
            print(json.dumps(scored, indent=2)[:400])
        print(f"\n[dry-run] would write {len(findings)} enriched + {len(findings)} scored objects")
        return 0

    s3 = boto3.client("s3")
    written = 0
    for f in findings:
        # enriched/
        s3.put_object(
            Bucket=args.bucket,
            Key=s3_key("enriched", f),
            Body=json.dumps(f).encode("utf-8"),
            ContentType="application/json",
            ServerSideEncryption="aws:kms",
        )
        # scored/
        scored = to_scored(f)
        s3.put_object(
            Bucket=args.bucket,
            Key=s3_key("scored", scored),
            Body=json.dumps(scored).encode("utf-8"),
            ContentType="application/json",
            ServerSideEncryption="aws:kms",
        )
        written += 2

    print(f"Wrote {written} objects to s3://{args.bucket}/ (enriched/ + scored/)")
    print("Next: trigger a Knowledge Base ingestion job (sync) - see 06-genai README.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
