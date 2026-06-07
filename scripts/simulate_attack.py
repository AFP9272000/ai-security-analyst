"""
Attack simulation for the AI Security Analyst demo.

Generates realistic findings to watch the full pipeline work:
detection -> EventBridge -> enricher -> enriched/ S3 -> Bedrock KB ->
agent -> auto-triage alert.

Two trigger types:
  1. GuardDuty sample findings (--guardduty): exercises the GuardDuty ->
     EventBridge -> triage path and the GuardDuty -> Security Hub
     aggregation. Sample severities vary; not all cross the HIGH bar.
  2. A custom HIGH Security Hub finding via BatchImportFindings (--inject):
     the DETERMINISTIC demo trigger. It's HIGH severity, NEW, and ACTIVE,
     so it always fires the Security Hub triage rule. A fresh UUID each
     run means dedup never suppresses it, re-run for a fresh alert.

Optional --sync-kb starts ingestion so injected/enriched findings reach
the knowledge base (so the agent can answer questions about them).

Usage (from repo root):
    $env:AWS_PROFILE = "security-tooling"
    python scripts/simulate_attack.py --all
    python scripts/simulate_attack.py --inject
    python scripts/simulate_attack.py --sync-kb <knowledge_base_id>
"""
from __future__ import annotations

import argparse
import json
import sys
import uuid
from datetime import datetime, timezone

import boto3

# GuardDuty sample types to generate. A mix; the EventBridge rule only
# alerts on severity >= 7, so the deterministic HIGH alert comes from the
# Security Hub injection below.
DEFAULT_GD_TYPES = [
    "UnauthorizedAccess:EC2/SSHBruteForce",
    "CryptoCurrency:EC2/BitcoinTool.B!DNS",
    "Trojan:EC2/DNSDataExfiltration",
]


def _now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


def _account_id(region: str) -> str:
    return boto3.client("sts", region_name=region).get_caller_identity()["Account"]


def trigger_guardduty_samples(region: str, finding_types: list[str]):
    gd = boto3.client("guardduty", region_name=region)
    detectors = gd.list_detectors().get("DetectorIds", [])
    if not detectors:
        print("  ! No GuardDuty detector in this account/region; skipping samples.")
        return None
    detector = detectors[0]
    gd.create_sample_findings(DetectorId=detector, FindingTypes=finding_types)
    print(f"  GuardDuty: created {len(finding_types)} sample finding type(s) on {detector}.")
    return detector


def inject_securityhub_finding(region: str, account_id: str) -> str:
    sh = boto3.client("securityhub", region_name=region)
    finding_id = f"ai-sec-analyst-demo/{uuid.uuid4()}"
    ts = _now_iso()
    finding = {
        "SchemaVersion": "2018-10-08",
        "Id": finding_id,
        "ProductArn": f"arn:aws:securityhub:{region}:{account_id}:product/{account_id}/default",
        "GeneratorId": "ai-sec-analyst-demo",
        "AwsAccountId": account_id,
        "Types": ["Software and Configuration Checks/Vulnerabilities/CVE"],
        "FirstObservedAt": ts,
        "CreatedAt": ts,
        "UpdatedAt": ts,
        "Severity": {"Label": "HIGH", "Normalized": 70},
        "Title": "Public S3 bucket hosting software with a known CVE",
        "Description": (
            "Demo finding: an S3 bucket is publicly accessible and serves an "
            "application with a known critical CVE. Injected by the attack "
            "simulation to exercise the detection-to-triage pipeline end to end."
        ),
        "Resources": [{
            "Type": "AwsS3Bucket",
            "Id": f"arn:aws:s3:::ai-sec-analyst-demo-{account_id}",
            "Region": region,
        }],
        "ProductFields": {"ai-sec-analyst/demo": "true"},
        "RecordState": "ACTIVE",
    }
    resp = sh.batch_import_findings(Findings=[finding])
    if resp.get("FailedCount", 0):
        print("  ! Security Hub import had failures:")
        print(json.dumps(resp.get("FailedFindings", []), indent=2))
    else:
        print(f"  Security Hub: injected HIGH finding {finding_id}")
    return finding_id


def sync_knowledge_base(region: str, kb_id: str) -> None:
    agent = boto3.client("bedrock-agent", region_name=region)
    sources = agent.list_data_sources(knowledgeBaseId=kb_id).get("dataSourceSummaries", [])
    if not sources:
        print(f"  ! No data sources on KB {kb_id}; skipping sync.")
        return
    for ds in sources:
        agent.start_ingestion_job(knowledgeBaseId=kb_id, dataSourceId=ds["dataSourceId"])
        print(f"  KB: started ingestion for data source {ds['dataSourceId']} ({ds.get('name', '')})")
    print("  KB: ingestion started (usually completes in a few minutes).")


def _print_watch_guidance(region: str, finding_id: str | None) -> None:
    print("\nWatch the pipeline:")
    print(f"  Triage logs:   aws logs tail /aws/lambda/ai-sec-analyst-triage --region {region} --follow")
    print(f"  GuardDuty:     console -> GuardDuty -> Findings (sample findings flagged [SAMPLE])")
    if finding_id:
        print("  Security Hub:  console -> Security Hub -> Findings -> filter Title 'Public S3 bucket'")
    print(f"  Enriched S3:   aws s3 ls s3://<enriched-bucket>/enriched/ --recursive --region {region} | Select-Object -Last 5")
    print("  The alert:     check your email for the [HIGH] triage alert with the agent's assessment.")
    print("  Ask the agent: python scripts/chat_client.py ... --question \"What new HIGH findings arrived and how should I respond?\"")


def main() -> None:
    parser = argparse.ArgumentParser(description="Simulate findings for the AI Security Analyst demo.")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--guardduty", action="store_true", help="Create GuardDuty sample findings")
    parser.add_argument("--inject", action="store_true", help="Inject a custom HIGH Security Hub finding (deterministic alert)")
    parser.add_argument("--sync-kb", metavar="KB_ID", help="Start ingestion on the given knowledge base id")
    parser.add_argument("--all", action="store_true", help="GuardDuty samples + Security Hub injection")
    args = parser.parse_args()

    if not (args.guardduty or args.inject or args.sync_kb or args.all):
        parser.error("choose at least one action: --guardduty, --inject, --sync-kb, or --all")

    region = args.region
    account = _account_id(region)
    print(f"Account {account}, region {region}\n")

    finding_id = None
    if args.guardduty or args.all:
        trigger_guardduty_samples(region, DEFAULT_GD_TYPES)
    if args.inject or args.all:
        finding_id = inject_securityhub_finding(region, account)
    if args.sync_kb:
        sync_knowledge_base(region, args.sync_kb)

    _print_watch_guidance(region, finding_id)


if __name__ == "__main__":
    main()
