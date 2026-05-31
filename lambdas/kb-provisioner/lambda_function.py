"""
Knowledge Base vector-store provisioner.

Runs the pgvector DDL the Bedrock Knowledge Base requires, via the RDS
Data API. Invoked once at terraform apply time (aws_lambda_invocation).

Why the Data API instead of a VPC-attached psycopg2 Lambda: the Data API
is an HTTPS control path, so this Lambda needs no VPC, no ENI, no
security-group plumbing which also means it can't hang a teardown the
way VPC Lambdas do. All statements use IF NOT EXISTS, so re-invocation
on subsequent applies is harmless and idempotent.

Cold-start handling: if the cluster is paused (scaled to 0 ACUs), the
first Data API call triggers a resume and may raise a transient error.
We retry with backoff until the cluster is awake.

Environment variables:
    CLUSTER_ARN    Aurora cluster ARN
    SECRET_ARN     RDS-managed master-password secret ARN
    DATABASE_NAME  Logical database name (e.g. "kb")
    SCHEMA_NAME    Target schema (e.g. "bedrock_kb")
    TABLE_NAME     Vector table name (e.g. "findings")
    VECTOR_DIMS    Embedding dimensions (e.g. "1024")
"""
from __future__ import annotations

import logging
import os
import time
from typing import Any

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds_data = boto3.client("rds-data")

CLUSTER_ARN = os.environ["CLUSTER_ARN"]
SECRET_ARN = os.environ["SECRET_ARN"]
DATABASE_NAME = os.environ["DATABASE_NAME"]
SCHEMA_NAME = os.environ["SCHEMA_NAME"]
TABLE_NAME = os.environ["TABLE_NAME"]
VECTOR_DIMS = int(os.environ.get("VECTOR_DIMS", "1024"))

# Errors that mean "cluster is waking up, try again"
_RESUME_HINTS = ("resuming", "is being resumed", "not currently available", "DatabaseResuming")


def _execute(sql: str, max_attempts: int = 12, base_delay: float = 5.0) -> None:
    """Execute one SQL statement via the Data API, retrying on resume."""
    attempt = 0
    while True:
        attempt += 1
        try:
            rds_data.execute_statement(
                resourceArn=CLUSTER_ARN,
                secretArn=SECRET_ARN,
                database=DATABASE_NAME,
                sql=sql,
            )
            logger.info("OK: %s", sql.split("\n")[0][:80])
            return
        except ClientError as exc:
            msg = str(exc)
            resuming = any(hint.lower() in msg.lower() for hint in _RESUME_HINTS)
            if resuming and attempt < max_attempts:
                delay = base_delay * min(attempt, 6)
                logger.info("Cluster resuming (attempt %d/%d); sleeping %.0fs",
                            attempt, max_attempts, delay)
                time.sleep(delay)
                continue
            logger.exception("Statement failed: %s", sql.split("\n")[0][:80])
            raise


def handler(event: dict[str, Any], context: Any) -> dict[str, Any]:
    """Create the extension, schema, vector table, and indexes."""
    qualified = f"{SCHEMA_NAME}.{TABLE_NAME}"

    statements = [
        # pgvector extension
        "CREATE EXTENSION IF NOT EXISTS vector;",

        # dedicated schema
        f"CREATE SCHEMA IF NOT EXISTS {SCHEMA_NAME};",

        # vector table - column names match the Bedrock field_mapping in
        # knowledge-base.tf (id / embedding / chunk / metadata)
        f"""
        CREATE TABLE IF NOT EXISTS {qualified} (
            id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
            embedding vector({VECTOR_DIMS}),
            chunk text,
            metadata json
        );
        """,

        # HNSW index for cosine-distance vector search (matches the
        # similarity metric Bedrock uses by default)
        f"""
        CREATE INDEX IF NOT EXISTS {TABLE_NAME}_embedding_idx
            ON {qualified} USING hnsw (embedding vector_cosine_ops);
        """,

        # GIN text index - enables Bedrock hybrid (semantic + keyword)
        # search over the chunk column
        f"""
        CREATE INDEX IF NOT EXISTS {TABLE_NAME}_chunk_idx
            ON {qualified} USING gin (to_tsvector('simple', chunk));
        """,
    ]

    for sql in statements:
        _execute(sql.strip())

    logger.info("Vector store provisioned: %s (vector dims=%d)", qualified, VECTOR_DIMS)
    return {
        "status": "ok",
        "table": qualified,
        "vector_dimensions": VECTOR_DIMS,
    }
