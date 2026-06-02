"""
Unit tests for the orchestrator's request/response helpers.

These cover the pure logic (parsing, validation, identity extraction,
response envelope). The AWS-calling paths (_invoke_agent, _store_turn)
are integration-tested by actually hitting the deployed API.

Run from repo root:
    python -m pytest tests/unit/test_orchestrator.py -v
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / "lambdas" / "orchestrator"))

# Required env vars are read at import time; set placeholders.
os.environ.setdefault("AGENT_ID", "TESTAGENT")
os.environ.setdefault("CONVERSATION_TABLE", "test-conversations")

import lambda_function as orch  # noqa: E402


def test_parse_request_valid():
    event = {"body": json.dumps({"question": "what findings are high risk?"})}
    req, err = orch._parse_request(event)
    assert err is None
    assert req["question"] == "what findings are high risk?"
    assert req["session_id"].startswith("sess-")


def test_parse_request_keeps_supplied_session_id():
    event = {"body": json.dumps({"question": "hi", "session_id": "sess-abc123"})}
    req, err = orch._parse_request(event)
    assert err is None
    assert req["session_id"] == "sess-abc123"


def test_parse_request_missing_question():
    event = {"body": json.dumps({"session_id": "sess-x"})}
    req, err = orch._parse_request(event)
    assert req is None
    assert "question" in err.lower()


def test_parse_request_empty_question():
    event = {"body": json.dumps({"question": "   "})}
    req, err = orch._parse_request(event)
    assert req is None
    assert "required" in err.lower()


def test_parse_request_bad_json():
    event = {"body": "{not json"}
    req, err = orch._parse_request(event)
    assert req is None
    assert "json" in err.lower()


def test_parse_request_missing_body():
    event = {}
    req, err = orch._parse_request(event)
    # No body -> "{}" -> missing question
    assert req is None
    assert "question" in err.lower()


def test_parse_request_question_too_long():
    event = {"body": json.dumps({"question": "x" * 5000})}
    req, err = orch._parse_request(event)
    assert req is None
    assert "too long" in err.lower()


def test_parse_request_non_object_body():
    event = {"body": json.dumps(["not", "an", "object"])}
    req, err = orch._parse_request(event)
    assert req is None
    assert "object" in err.lower()


def test_user_from_claims_sub():
    event = {"requestContext": {"authorizer": {"jwt": {"claims": {"sub": "user-123"}}}}}
    assert orch._user_from_claims(event) == "user-123"


def test_user_from_claims_username_fallback():
    event = {"requestContext": {"authorizer": {"jwt": {"claims": {"cognito:username": "addison"}}}}}
    assert orch._user_from_claims(event) == "addison"


def test_user_from_claims_missing():
    assert orch._user_from_claims({}) == "unknown"


def test_build_response_shape():
    resp = orch._build_response(200, {"answer": "hello"})
    assert resp["statusCode"] == 200
    assert resp["headers"]["Content-Type"] == "application/json"
    assert json.loads(resp["body"]) == {"answer": "hello"}
