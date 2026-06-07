"""
Triage Lambda, the reflex of the SOC copilot.

Trigger: an EventBridge rule fires on a high-severity GuardDuty or
Security Hub finding. This Lambda:
  1. Parses the finding (both schemas) into a normalized shape.
  2. DEDUPLICATES by finding ID (suppresses re-imports of the same
     finding within a window), see below.
  3. Optionally asks the Bedrock agent to triage it (risk + next steps).
  4. Publishes a formatted alert to SNS (email) and optionally Slack.

DEDUP: Security Hub and GuardDuty re-import the SAME finding repeatedly
(re-sends, compliance re-runs, occurrence-count ticks), each firing the
rule. To avoid one-alert-per-import, we claim the finding ID in a
DynamoDB table with a conditional write (succeeds only if not seen) and a
TTL. A claim that succeeds means it's new -> alert; a claim that fails
means we already alerted on it recently -> skip. If the alert publish
then fails, we release the claim so an EventBridge retry can re-deliver.

FAIL-SAFE: the alert is never blocked on the agent. If triage is
disabled, errors, or the KB is cold, the alert still goes out with the
raw finding details.

Environment variables:
    SNS_TOPIC_ARN        Alert topic (required)
    AGENT_ID             Bedrock agent id (required)
    AGENT_ALIAS_ID       Alias to invoke (default TSTALIASID)
    ENABLE_AGENT_TRIAGE  "true"/"false" (default "true")
    DEDUP_TABLE          DynamoDB dedup table name (dedup disabled if unset)
    DEDUP_TTL_HOURS      Suppress repeats for this many hours (default 24)
    SLACK_WEBHOOK_PARAM  SSM param name with a Slack webhook URL (optional)
    MAX_RESUME_RETRIES   Aurora cold-start retries (default 5)
"""
from __future__ import annotations

import json
import logging
import os
import time
import urllib.request

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

SNS_TOPIC_ARN = os.environ["SNS_TOPIC_ARN"]
AGENT_ID = os.environ["AGENT_ID"]
AGENT_ALIAS_ID = os.environ.get("AGENT_ALIAS_ID", "TSTALIASID")
ENABLE_AGENT_TRIAGE = os.environ.get("ENABLE_AGENT_TRIAGE", "true").lower() == "true"
DEDUP_TABLE = os.environ.get("DEDUP_TABLE", "")
DEDUP_TTL_HOURS = int(os.environ.get("DEDUP_TTL_HOURS", "24"))
SLACK_WEBHOOK_PARAM = os.environ.get("SLACK_WEBHOOK_PARAM", "")
MAX_RESUME_RETRIES = int(os.environ.get("MAX_RESUME_RETRIES", "5"))

_clients: dict = {}
_resources: dict = {}


def _client(name: str):
    if name not in _clients:
        _clients[name] = boto3.client(name)
    return _clients[name]


def _resource(name: str):
    if name not in _resources:
        _resources[name] = boto3.resource(name)
    return _resources[name]


def handler(event, context):
    finding = parse_finding(event)
    logger.info("triage: kind=%s id=%s sev=%s account=%s",
                finding["kind"], finding["id"], finding["severity"], finding["account"])

    # Dedup: claim the finding id; skip if we've already alerted recently.
    if not _claim_finding(finding["id"]):
        logger.info("duplicate finding %s within dedup window; suppressing", finding["id"])
        return {"status": "suppressed_duplicate", "finding_id": finding["id"]}

    triage = None
    if ENABLE_AGENT_TRIAGE:
        try:
            triage = triage_with_agent(finding)
        except Exception:  # noqa: BLE001 - fail-safe, never block the alert
            logger.exception("agent triage failed; sending alert without it")

    subject, body = format_alert(finding, triage)

    try:
        _client("sns").publish(TopicArn=SNS_TOPIC_ARN, Subject=subject, Message=body)
    except Exception:  # noqa: BLE001
        logger.exception("SNS publish failed")
        _release_finding(finding["id"])  # let a retry re-deliver
        raise

    _maybe_post_slack(subject, body)

    return {"status": "alerted", "finding_id": finding["id"], "triaged": triage is not None}


# --- Deduplication -----------------------------------------------------------

def _claim_finding(finding_id: str) -> bool:
    """Claim a finding id. Returns True if newly claimed (should alert),
    False if it was already claimed within the TTL window (suppress).
    Fails open: if dedup is unconfigured or DynamoDB errors, we alert."""
    if not DEDUP_TABLE:
        return True
    try:
        _resource("dynamodb").Table(DEDUP_TABLE).put_item(
            Item={
                "finding_id": finding_id,
                "ttl": int(time.time()) + DEDUP_TTL_HOURS * 3600,
            },
            ConditionExpression="attribute_not_exists(finding_id)",
        )
        return True
    except ClientError as exc:
        if exc.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            return False  # already alerted recently
        logger.exception("dedup claim error; failing open (will alert)")
        return True
    except Exception:  # noqa: BLE001
        logger.exception("dedup claim error; failing open (will alert)")
        return True


def _release_finding(finding_id: str) -> None:
    """Delete a dedup claim so a retry can re-alert (used on publish failure)."""
    if not DEDUP_TABLE:
        return
    try:
        _resource("dynamodb").Table(DEDUP_TABLE).delete_item(Key={"finding_id": finding_id})
    except Exception:  # noqa: BLE001
        logger.exception("dedup release failed (non-fatal)")


# --- Parsing / formatting (pure) ---------------------------------------------

def parse_finding(event: dict) -> dict:
    """Normalize a GuardDuty or Security Hub EventBridge event. Pure."""
    source = event.get("source", "")
    detail = event.get("detail", {}) or {}

    if source == "aws.guardduty":
        resource = detail.get("resource", {}) or {}
        return {
            "kind": "GuardDuty",
            "id": detail.get("id", "unknown"),
            "title": detail.get("type", "Unknown finding type"),
            "severity": detail.get("severity", "unknown"),
            "account": detail.get("accountId") or event.get("account", "unknown"),
            "region": detail.get("region") or event.get("region", "unknown"),
            "description": detail.get("description", ""),
            "resource": resource.get("resourceType", "unknown"),
        }

    if source == "aws.securityhub":
        findings = detail.get("findings") or [{}]
        f = findings[0] if findings else {}
        resources = f.get("Resources") or [{}]
        return {
            "kind": "SecurityHub",
            "id": f.get("Id", "unknown"),
            "title": f.get("Title", "Unknown finding"),
            "severity": (f.get("Severity") or {}).get("Label", "unknown"),
            "account": f.get("AwsAccountId") or event.get("account", "unknown"),
            "region": f.get("Region") or event.get("region", "unknown"),
            "description": f.get("Description", ""),
            "resource": (resources[0] or {}).get("Type", "unknown"),
        }

    return {
        "kind": source or "Unknown",
        "id": detail.get("id", "unknown"),
        "title": detail.get("type") or detail.get("title", "Unknown finding"),
        "severity": detail.get("severity", "unknown"),
        "account": event.get("account", "unknown"),
        "region": event.get("region", "unknown"),
        "description": detail.get("description", ""),
        "resource": "unknown",
    }


def format_alert(finding: dict, triage: str | None) -> tuple[str, str]:
    """Build the (subject, body) for the alert. Pure. Subject capped at 100."""
    subject = f"[{finding['severity']}] {finding['kind']} finding in account {finding['account']}"
    if len(subject) > 100:
        subject = subject[:97] + "..."

    lines = [
        f"A {finding['kind']} security finding was detected.",
        "",
        f"Title:     {finding['title']}",
        f"Severity:  {finding['severity']}",
        f"Account:   {finding['account']}",
        f"Region:    {finding['region']}",
        f"Resource:  {finding['resource']}",
        f"Finding ID: {finding['id']}",
    ]
    if finding.get("description"):
        lines += ["", "Description:", finding["description"][:800]]
    if triage:
        lines += ["", "----- AI analyst triage -----", triage]
    else:
        lines += ["", "(Automated triage was not attached to this alert.)"]
    lines += ["", "-- AI Security Analyst (automated alert)"]
    return subject, "\n".join(lines)


# --- Agent triage ------------------------------------------------------------

def triage_with_agent(finding: dict) -> str:
    """Ask the agent to assess the finding. Retries Aurora cold starts."""
    prompt = (
        f"A new {finding['kind']} security finding was just detected and needs triage.\n"
        f"Title: {finding['title']}\n"
        f"Severity: {finding['severity']}\n"
        f"Account: {finding['account']}\n"
        f"Region: {finding['region']}\n"
        f"Resource type: {finding['resource']}\n"
        f"Finding ID: {finding['id']}\n"
        f"Description: {finding['description'][:500]}\n\n"
        "Give a brief risk assessment (2-3 sentences) and the top 2-3 "
        "recommended immediate actions. If similar findings exist in the "
        "knowledge base, note any pattern. Be concise."
    )

    runtime = _client("bedrock-agent-runtime")
    session_id = f"triage-{finding['id']}"[:100]
    last_exc = None

    for attempt in range(1, MAX_RESUME_RETRIES + 1):
        try:
            response = runtime.invoke_agent(
                agentId=AGENT_ID,
                agentAliasId=AGENT_ALIAS_ID,
                sessionId=session_id,
                inputText=prompt,
            )
            parts = []
            for ev in response["completion"]:
                if "chunk" in ev:
                    parts.append(ev["chunk"].get("bytes", b"").decode("utf-8", "replace"))
            return "".join(parts).strip()
        except Exception as exc:  # noqa: BLE001
            msg = str(exc).lower()
            cold = "resum" in msg or "auto-pause" in msg or "dependencyfailed" in msg
            if cold and attempt < MAX_RESUME_RETRIES:
                wait = 5 * attempt
                logger.info("KB cluster resuming; triage retry %d in %ds", attempt, wait)
                time.sleep(wait)
                last_exc = exc
                continue
            raise

    raise last_exc  # type: ignore[misc]


def _maybe_post_slack(subject: str, body: str) -> None:
    if not SLACK_WEBHOOK_PARAM:
        return
    try:
        param = _client("ssm").get_parameter(Name=SLACK_WEBHOOK_PARAM, WithDecryption=True)
        webhook = param["Parameter"]["Value"]
        payload = json.dumps({"text": f"*{subject}*\n```{body}```"}).encode("utf-8")
        req = urllib.request.Request(
            webhook, data=payload, method="POST",
            headers={"Content-Type": "application/json"},
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            resp.read()
    except Exception:  # noqa: BLE001 - Slack is best-effort
        logger.exception("Slack post failed (non-fatal)")
