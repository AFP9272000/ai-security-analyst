"""
Orchestrator Lambda, the API front door's compute.

Flow: API Gateway (HTTP API, Cognito-authorized) -> this Lambda ->
Bedrock Agent (InvokeAgent, streamed) -> buffer the answer -> persist the
turn to DynamoDB -> return JSON.

This is the productionized version of scripts/ask_agent.py: it consumes
the agent's EventStream server-side and returns a single JSON response,
so API Gateway does plain request/response (no client-side streaming to
manage).

Aurora cold-start handling: the KB's Aurora cluster scales to zero when
idle. The first agent invocation after a pause can fail with a "resuming
after being auto-paused" / DependencyFailedException error. We retry with
backoff so the caller sees a slightly slower first response instead of an
error. (Same behavior observed in the Bedrock console test panel.)

Environment variables:
    AGENT_ID             Bedrock agent id
    AGENT_ALIAS_ID       Alias to invoke (default TSTALIASID = working draft)
    CONVERSATION_TABLE   DynamoDB table name
    HISTORY_TTL_DAYS     Days to retain history (default 30)
    MAX_RESUME_RETRIES   Cold-start retries (default 3)
"""
from __future__ import annotations

import json
import logging
import os
import time
import uuid
from datetime import datetime, timedelta, timezone

import boto3

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

AGENT_ID = os.environ["AGENT_ID"]
AGENT_ALIAS_ID = os.environ.get("AGENT_ALIAS_ID", "TSTALIASID")
CONVERSATION_TABLE = os.environ["CONVERSATION_TABLE"]
HISTORY_TTL_DAYS = int(os.environ.get("HISTORY_TTL_DAYS", "30"))
MAX_RESUME_RETRIES = int(os.environ.get("MAX_RESUME_RETRIES", "3"))

# Lazy client/resource init so importing the module (e.g. in unit tests)
# doesn't require AWS credentials or a region.
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
    request, error = _parse_request(event)
    if error:
        return _build_response(400, {"error": error})

    user_id = _user_from_claims(event)
    session_id = request["session_id"]
    question = request["question"]

    logger.info("chat request user=%s session=%s", user_id, session_id)

    try:
        answer = _invoke_agent(session_id, question)
    except Exception as exc:  # noqa: BLE001
        logger.exception("agent invocation failed")
        return _build_response(502, {
            "error": "The assistant is temporarily unavailable. Please try again.",
            "detail": str(exc)[:300],
            "session_id": session_id,
        })

    # History write is best-effort: a failure here shouldn't fail the chat.
    try:
        _store_turn(session_id, user_id, question, answer)
    except Exception:  # noqa: BLE001
        logger.exception("history write failed (non-fatal)")

    return _build_response(200, {"session_id": session_id, "answer": answer})


def _parse_request(event):
    """Validate the HTTP body. Returns (request_dict, error_message)."""
    raw = event.get("body") or "{}"
    try:
        body = json.loads(raw)
    except json.JSONDecodeError:
        return None, "Request body must be valid JSON."

    if not isinstance(body, dict):
        return None, "Request body must be a JSON object."

    question = (body.get("question") or "").strip()
    if not question:
        return None, "Field 'question' is required."
    if len(question) > 4000:
        return None, "Field 'question' is too long (max 4000 chars)."

    session_id = (body.get("session_id") or f"sess-{uuid.uuid4().hex[:16]}").strip()
    return {"question": question, "session_id": session_id}, None


def _user_from_claims(event):
    """Pull the caller's identity from the Cognito JWT claims (HTTP API v2)."""
    claims = (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("jwt", {})
        .get("claims", {})
    )
    return claims.get("sub") or claims.get("cognito:username") or "unknown"


def _invoke_agent(session_id: str, question: str) -> str:
    """Invoke the agent and buffer its streamed answer, retrying on cold start."""
    runtime = _client("bedrock-agent-runtime")
    last_exc = None

    for attempt in range(1, MAX_RESUME_RETRIES + 1):
        try:
            response = runtime.invoke_agent(
                agentId=AGENT_ID,
                agentAliasId=AGENT_ALIAS_ID,
                sessionId=session_id,
                inputText=question,
            )
            parts = []
            for ev in response["completion"]:
                if "chunk" in ev:
                    parts.append(ev["chunk"].get("bytes", b"").decode("utf-8", "replace"))
            return "".join(parts).strip()

        except Exception as exc:  # noqa: BLE001
            msg = str(exc).lower()
            is_cold_start = (
                "resum" in msg
                or "auto-pause" in msg
                or "auto-paused" in msg
                or "dependencyfailed" in msg
            )
            if is_cold_start and attempt < MAX_RESUME_RETRIES:
                wait = 5 * attempt
                logger.info("vector store resuming; retry %d/%d in %ds",
                            attempt, MAX_RESUME_RETRIES, wait)
                time.sleep(wait)
                last_exc = exc
                continue
            raise

    # Exhausted retries on a cold-start error
    raise last_exc  # type: ignore[misc]


def _store_turn(session_id: str, user_id: str, question: str, answer: str) -> None:
    table = _resource("dynamodb").Table(CONVERSATION_TABLE)
    now = datetime.now(timezone.utc)
    table.put_item(Item={
        "session_id": session_id,
        "timestamp": now.isoformat(),
        "user_id": user_id,
        "question": question,
        "answer": answer,
        "ttl": int((now + timedelta(days=HISTORY_TTL_DAYS)).timestamp()),
    })


def _build_response(status: int, body: dict) -> dict:
    return {
        "statusCode": status,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps(body),
    }
