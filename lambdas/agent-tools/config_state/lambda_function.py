"""
Config state tool - a Bedrock Agent action group.

Lets the agent look up the CURRENT configuration of an AWS resource via
AWS Config's advanced query (select_resource_config). Useful for
grounding an answer in live resource state rather than just the
finding's point-in-time snapshot.

v1 scope: queries the LOCAL account's Config recordings (security-
tooling). For org-wide resource state you would point this at a Config
aggregator (select_aggregate_resource_config) - noted as a future
enhancement in the README.

Input is validated against a strict character allowlist before being
placed in the Config query expression - resource identifiers are
alphanumeric plus a small set of punctuation, so anything else is
rejected rather than escaped.

Environment variables: none required.
"""
from __future__ import annotations

import json
import logging
import os
import re
from typing import Any

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

config_client = boto3.client("config")

# Resource IDs / ARNs are alphanumeric plus - _ / : . and spaces are not
# allowed. Reject anything else to keep the Config expression safe.
_SAFE_ID = re.compile(r"^[A-Za-z0-9\-_/:.]{1,256}$")


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    logger.info("Config tool invoked: function=%s", event.get("function"))
    params = {p["name"]: p.get("value") for p in event.get("parameters", [])}
    resource_id = (params.get("resource_id") or "").strip()

    if not resource_id:
        return _respond(event, "No resource_id provided.")

    if not _SAFE_ID.match(resource_id):
        return _respond(event, "Invalid resource_id format.")

    # If an ARN was passed, the last segment is usually the resourceId
    # Config indexes on. Try the raw value first, then the ARN tail.
    candidates = [resource_id]
    if ":" in resource_id or "/" in resource_id:
        tail = re.split(r"[:/]", resource_id)[-1]
        if tail and tail != resource_id and _SAFE_ID.match(tail):
            candidates.append(tail)

    try:
        for candidate in candidates:
            expr = (
                "SELECT resourceId, resourceType, awsRegion, "
                "configuration, configurationItemCaptureTime "
                f"WHERE resourceId = '{candidate}'"
            )
            resp = config_client.select_resource_config(Expression=expr, Limit=3)
            results = resp.get("Results", [])
            if results:
                return _respond(event, _format_results(candidate, results))

        return _respond(
            event,
            f"No current Config record found for '{resource_id}' in this account. "
            "It may be in another account (org-wide lookup not enabled in v1) or "
            "of a type Config does not record.",
        )
    except Exception as exc:  # noqa: BLE001
        logger.exception("Config tool failed")
        return _respond(event, f"Config lookup failed: {exc}")


def _format_results(resource_id: str, results: list[str]) -> str:
    """Each result is a JSON string; summarize concisely for the agent."""
    lines = [f"Config record(s) for '{resource_id}':"]
    for raw in results:
        try:
            item = json.loads(raw)
        except (json.JSONDecodeError, TypeError):
            lines.append(f"- (unparseable result: {str(raw)[:120]})")
            continue
        lines.append(
            f"- type={item.get('resourceType')} region={item.get('awsRegion')} "
            f"captured={item.get('configurationItemCaptureTime')}"
        )
        cfg = item.get("configuration")
        if cfg is not None:
            cfg_str = json.dumps(cfg) if not isinstance(cfg, str) else cfg
            lines.append(f"  configuration: {cfg_str[:600]}")
    return "\n".join(lines)


def _respond(event: dict[str, Any], body: str) -> dict[str, Any]:
    return {
        "messageVersion": "1.0",
        "response": {
            "actionGroup": event.get("actionGroup", ""),
            "function": event.get("function", ""),
            "functionResponse": {
                "responseBody": {"TEXT": {"body": body}}
            },
        },
    }
