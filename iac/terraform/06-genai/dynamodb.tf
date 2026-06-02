# DynamoDB - conversation history (in Security Tooling)
#
# Durable, app-controlled record of every chat turn. Distinct from the
# agent's own Bedrock session memory (which gives the agent in-flight
# conversational context via sessionId): this table is what WE persist
# for display, audit, and cross-session history.
#
# Key design:
#   PK session_id (S) + SK timestamp (S) -> a session's turns sort
#   chronologically, and "get this conversation" is a single Query.
# TTL on `ttl` auto-expires old turns. On-demand billing (pennies at
# demo volume). Encrypted with the security-tooling baseline CMK.

resource "aws_dynamodb_table" "conversations" {
  provider = aws.security_tooling

  name         = "${var.project}-conversations"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "session_id"
  range_key    = "timestamp"

  attribute {
    name = "session_id"
    type = "S"
  }
  attribute {
    name = "timestamp"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.security_tooling_kms_arn
  }

  point_in_time_recovery {
    enabled = true
  }
}
