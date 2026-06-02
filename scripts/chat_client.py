"""
End-to-end chat client: authenticate with Cognito, call the chat API.

Proves the full front door works: Cognito auth -> JWT -> API Gateway
(authorizer) -> orchestrator Lambda -> agent -> answer.

Usage (from repo root):
    $env:AWS_PROFILE = "security-tooling"
    python scripts/chat_client.py `
      --client-id <cognito_app_client_id> `
      --username analyst@example.com `
      --password 'YourTempOrPermPassword' `
      --api-url <chat_api_endpoint> `
      --question "What are the highest-risk findings this week?"

Pass --session-id to continue a prior conversation. Get the client-id and
api-url from the 06-genai terraform outputs (or via the AWS CLI).
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
import uuid

import boto3


def get_id_token(client_id: str, username: str, password: str, region: str) -> str:
    idp = boto3.client("cognito-idp", region_name=region)
    resp = idp.initiate_auth(
        ClientId=client_id,
        AuthFlow="USER_PASSWORD_AUTH",
        AuthParameters={"USERNAME": username, "PASSWORD": password},
    )
    if "AuthenticationResult" not in resp:
        # e.g. NEW_PASSWORD_REQUIRED challenge on a freshly created user
        challenge = resp.get("ChallengeName", "unknown")
        raise SystemExit(
            f"Auth did not return tokens (challenge: {challenge}). "
            "If this is a new user, set a permanent password first - see the Part 3 README."
        )
    return resp["AuthenticationResult"]["IdToken"]


def call_chat(api_url: str, token: str, question: str, session_id: str) -> dict:
    url = api_url.rstrip("/") + "/chat"
    payload = json.dumps({"question": question, "session_id": session_id}).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        method="POST",
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {token}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", "replace")
        raise SystemExit(f"HTTP {exc.code}: {body}")


def main() -> None:
    parser = argparse.ArgumentParser(description="Chat with the security analyst API.")
    parser.add_argument("--client-id", required=True, help="Cognito app client id")
    parser.add_argument("--username", required=True)
    parser.add_argument("--password", required=True)
    parser.add_argument("--api-url", required=True, help="chat_api_endpoint output")
    parser.add_argument("--question", required=True)
    parser.add_argument("--session-id", default=f"sess-{uuid.uuid4().hex[:16]}")
    parser.add_argument("--region", default=os.environ.get("AWS_REGION", "us-east-1"))
    args = parser.parse_args()

    print("Authenticating with Cognito...", file=sys.stderr)
    token = get_id_token(args.client_id, args.username, args.password, args.region)

    print(f"Calling chat API (session {args.session_id})...\n", file=sys.stderr)
    result = call_chat(args.api_url, token, args.question, args.session_id)

    print(result.get("answer", json.dumps(result)))
    print(f"\n[session_id: {result.get('session_id', args.session_id)}]", file=sys.stderr)


if __name__ == "__main__":
    main()
