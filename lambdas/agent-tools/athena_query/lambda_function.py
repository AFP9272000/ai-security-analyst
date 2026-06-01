"""
Athena query tool - a Bedrock Agent action group.

Gives the agent precise, structured query access to the findings data
lake (the scored_findings Glue table). DESIGN CHOICE: the agent does NOT
write free-form SQL. It supplies structured parameters (severity,
source, days_back, only_anomalies, limit) and this Lambda builds a
safe, parameterized SELECT. This is both an injection guard and a
reliability win - the agent can't write malformed SQL or scan the whole
lake by accident. See docs/adr/0014.

Bedrock function-schema contract:
  Input event:  { function, parameters: [{name,type,value}], actionGroup, ... }
  Output:       { messageVersion, response: { actionGroup, function,
                  functionResponse: { responseBody: { TEXT: { body } } } } }

Environment variables:
    GLUE_DATABASE     e.g. ai_sec_analyst_security
    ATHENA_WORKGROUP  e.g. ai-sec-analyst-security
    FINDINGS_TABLE    default scored_findings
"""
from __future__ import annotations

import json
import logging
import os
import time
from typing import Any

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

athena = boto3.client("athena")

GLUE_DATABASE = os.environ["GLUE_DATABASE"]
ATHENA_WORKGROUP = os.environ["ATHENA_WORKGROUP"]
FINDINGS_TABLE = os.environ.get("FINDINGS_TABLE", "scored_findings")

# Allowlists - any value outside these is rejected, never interpolated
ALLOWED_SEVERITY = {"low", "medium", "high", "informational"}
ALLOWED_SOURCE = {"guardduty", "securityhub", "custom"}

MAX_LIMIT = 100
QUERY_POLL_SECONDS = 1.5
QUERY_MAX_WAIT = 40


def build_query(
    severity: str | None = None,
    source: str | None = None,
    days_back: Any = 7,
    only_anomalies: Any = False,
    limit: Any = 25,
) -> str:
    """
    Build a safe SELECT against the findings table.

    All string inputs are validated against allowlists; numeric inputs
    are cast to int; the boolean is normalized. No raw user text is
    interpolated into the SQL, so this is injection-safe by construction.
    """
    where: list[str] = []

    if severity:
        sev = str(severity).strip().lower()
        if sev not in ALLOWED_SEVERITY:
            raise ValueError(f"invalid severity '{severity}'; allowed: {sorted(ALLOWED_SEVERITY)}")
        where.append(f"severity = '{sev}'")

    if source:
        src = str(source).strip().lower()
        if src not in ALLOWED_SOURCE:
            raise ValueError(f"invalid source '{source}'; allowed: {sorted(ALLOWED_SOURCE)}")
        where.append(f"source = '{src}'")

    try:
        days = max(1, int(days_back))
    except (TypeError, ValueError):
        days = 7
    where.append(f"from_iso8601_timestamp(enriched_at) > (current_timestamp - interval '{days}' day)")

    if str(only_anomalies).strip().lower() in ("true", "1", "yes"):
        where.append("is_anomaly = true")

    try:
        lim = min(MAX_LIMIT, max(1, int(limit)))
    except (TypeError, ValueError):
        lim = 25

    clause = " AND ".join(where) if where else "1=1"
    return (
        "SELECT finding_id, source, severity, account_id, region, "
        "resource_arn, anomaly_score, is_anomaly, enriched_at "
        f"FROM {GLUE_DATABASE}.{FINDINGS_TABLE} "
        f"WHERE {clause} "
        "ORDER BY anomaly_score ASC "
        f"LIMIT {lim}"
    )


def run_query(sql: str) -> list[dict[str, str]]:
    """Execute the query in the configured workgroup; return rows as dicts."""
    start = athena.start_query_execution(
        QueryString=sql,
        WorkGroup=ATHENA_WORKGROUP,
    )
    qid = start["QueryExecutionId"]

    waited = 0.0
    while waited < QUERY_MAX_WAIT:
        execu = athena.get_query_execution(QueryExecutionId=qid)
        state = execu["QueryExecution"]["Status"]["State"]
        if state in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(QUERY_POLL_SECONDS)
        waited += QUERY_POLL_SECONDS
    else:
        raise TimeoutError(f"Athena query {qid} did not finish in {QUERY_MAX_WAIT}s")

    if state != "SUCCEEDED":
        reason = execu["QueryExecution"]["Status"].get("StateChangeReason", "unknown")
        raise RuntimeError(f"Athena query {state}: {reason}")

    results = athena.get_query_results(QueryExecutionId=qid, MaxResults=MAX_LIMIT + 1)
    rows = results["ResultSet"]["Rows"]
    if not rows:
        return []

    header = [c.get("VarCharValue", "") for c in rows[0]["Data"]]
    out = []
    for row in rows[1:]:
        values = [c.get("VarCharValue", "") for c in row["Data"]]
        out.append(dict(zip(header, values)))
    return out


def _params_to_dict(event: dict[str, Any]) -> dict[str, Any]:
    return {p["name"]: p.get("value") for p in event.get("parameters", [])}


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


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    logger.info("Athena tool invoked: function=%s", event.get("function"))
    params = _params_to_dict(event)

    try:
        sql = build_query(
            severity=params.get("severity"),
            source=params.get("source"),
            days_back=params.get("days_back", 7),
            only_anomalies=params.get("only_anomalies", False),
            limit=params.get("limit", 25),
        )
        logger.info("Query: %s", sql)
        rows = run_query(sql)

        if not rows:
            body = "No findings matched the query."
        else:
            lines = [f"{len(rows)} finding(s) matched (most anomalous first):"]
            for r in rows:
                lines.append(
                    f"- {r.get('finding_id')} | {r.get('source')} | sev={r.get('severity')} "
                    f"| acct={r.get('account_id')} | {r.get('region')} "
                    f"| anomaly_score={r.get('anomaly_score')} is_anomaly={r.get('is_anomaly')} "
                    f"| {r.get('resource_arn')}"
                )
            body = "\n".join(lines)

        return _respond(event, body)

    except ValueError as exc:
        return _respond(event, f"Invalid parameter: {exc}")
    except Exception as exc:  # noqa: BLE001
        logger.exception("Athena tool failed")
        return _respond(event, f"Query failed: {exc}")
