"""
Pre-demo readiness check for the AI Security Analyst.

Run this BEFORE a live demo to confirm every stage of the pipeline is in
place and the alert channel is live. Discovery-based (finds resources by
name pattern), single account (security-tooling), so run it with that
profile. Reports PASS / WARN / FAIL per check; nothing is mutated.

Usage:
    $env:AWS_PROFILE = "security-tooling"
    python scripts/preflight_check.py --region us-east-1
"""
from __future__ import annotations

import argparse
import sys

import boto3

PROJECT = "ai-sec-analyst"


def _status(ok: bool) -> str:
    return "PASS" if ok else "WARN"


def check(name: str, fn) -> bool:
    try:
        ok, detail = fn()
        print(f"  [{_status(ok)}] {name}: {detail}")
        return ok
    except Exception as exc:  # noqa: BLE001
        print(f"  [FAIL] {name}: {exc}")
        return False


def main() -> None:
    parser = argparse.ArgumentParser(description="Pre-demo readiness check.")
    parser.add_argument("--region", default="us-east-1")
    args = parser.parse_args()
    region = args.region

    print(f"AI Security Analyst - preflight ({region})\n")

    def caller():
        ident = boto3.client("sts", region_name=region).get_caller_identity()
        return True, f"account {ident['Account']}"

    def guardduty():
        gd = boto3.client("guardduty", region_name=region)
        dets = gd.list_detectors().get("DetectorIds", [])
        if not dets:
            return False, "no detector found"
        status = gd.get_detector(DetectorId=dets[0]).get("Status", "?")
        return status == "ENABLED", f"detector {dets[0]} status={status}"

    def securityhub():
        sh = boto3.client("securityhub", region_name=region)
        hub = sh.describe_hub()
        return True, f"enabled (subscribed {hub.get('SubscribedAt', '?')})"

    def enriched_bucket():
        s3 = boto3.client("s3", region_name=region)
        buckets = [b["Name"] for b in s3.list_buckets().get("Buckets", [])
                   if "enrich" in b["Name"].lower() and PROJECT in b["Name"].lower()]
        if not buckets:
            return False, "no enriched-findings bucket found by name"
        bucket = buckets[0]
        objs = s3.list_objects_v2(Bucket=bucket, Prefix="enriched/", MaxKeys=1)
        n = objs.get("KeyCount", 0)
        return True, f"{bucket} (enriched/ has objects: {'yes' if n else 'none yet'})"

    def triage_lambda():
        lam = boto3.client("lambda", region_name=region)
        fn = lam.get_function(FunctionName=f"{PROJECT}-triage")
        state = fn["Configuration"].get("State", "?")
        return state == "Active", f"{PROJECT}-triage state={state}"

    def dedup_table():
        ddb = boto3.client("dynamodb", region_name=region)
        t = ddb.describe_table(TableName=f"{PROJECT}-alert-dedup")
        return True, f"status={t['Table']['TableStatus']}"

    def alert_subscription():
        sns = boto3.client("sns", region_name=region)
        topic = next((t["TopicArn"] for t in sns.list_topics().get("Topics", [])
                      if f"{PROJECT}-alerts" in t["TopicArn"]), None)
        if not topic:
            return False, "alerts topic not found"
        subs = sns.list_subscriptions_by_topic(TopicArn=topic).get("Subscriptions", [])
        confirmed = [s for s in subs if s["SubscriptionArn"] not in ("PendingConfirmation", "Deleted")]
        if not subs:
            return False, "topic exists but has no subscriptions"
        if not confirmed:
            return False, "subscription(s) still PendingConfirmation - click the email link"
        return True, f"{len(confirmed)} confirmed subscription(s)"

    def aurora_warm():
        rds = boto3.client("rds", region_name=region)
        clusters = [c for c in rds.describe_db_clusters().get("DBClusters", [])
                    if PROJECT in c["DBClusterIdentifier"].lower()]
        if not clusters:
            return False, "no KB Aurora cluster found by name"
        c = clusters[0]
        cap = c.get("ServerlessV2ScalingConfiguration", {})
        return True, (f"{c['DBClusterIdentifier']} status={c['Status']} "
                      f"(min ACU {cap.get('MinCapacity', '?')}; first query may resume it)")

    checks = [
        ("Credentials / account", caller),
        ("GuardDuty enabled", guardduty),
        ("Security Hub enabled", securityhub),
        ("Enriched-findings bucket", enriched_bucket),
        ("Triage Lambda", triage_lambda),
        ("Dedup table", dedup_table),
        ("Alert subscription confirmed", alert_subscription),
        ("KB Aurora cluster", aurora_warm),
    ]

    results = [check(n, f) for n, f in checks]
    passed = sum(1 for r in results if r)
    print(f"\n{passed}/{len(results)} checks passed.")
    if passed < len(results):
        print("Resolve WARN/FAIL items above before a live demo (especially the alert subscription).")
        sys.exit(1)
    print("Ready. Pre-warm Aurora with one agent query ~30s before you present.")


if __name__ == "__main__":
    main()
