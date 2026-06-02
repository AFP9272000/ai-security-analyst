# Orchestrator Lambda (in Security Tooling)
#
# The compute behind the chat API: invokes the Bedrock agent, buffers the
# streamed answer, persists the turn to DynamoDB. No VPC (all API calls).

data "archive_file" "orchestrator" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/orchestrator"
  output_path = "${path.module}/.build/orchestrator.zip"
  excludes    = ["__pycache__", "*.pyc", "README.md"]
}

resource "aws_iam_role" "orchestrator" {
  provider           = aws.security_tooling
  name               = "${var.project}-orchestrator"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  description        = "Execution role for the chat orchestrator Lambda"
}

data "aws_iam_policy_document" "orchestrator" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-orchestrator",
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-orchestrator:*",
    ]
  }

  # Invoke the agent. InvokeAgent authorizes against the agent-alias ARN;
  # we allow any alias of THIS agent (covers both the working draft
  # TSTALIASID and the published `live` alias).
  statement {
    sid    = "InvokeAgent"
    effect = "Allow"
    actions = [
      "bedrock:InvokeAgent",
    ]
    resources = [
      aws_bedrockagent_agent.analyst.agent_arn,
      "arn:aws:bedrock:${var.region}:${local.security_tooling_id}:agent-alias/${aws_bedrockagent_agent.analyst.agent_id}/*",
    ]
  }

  # Conversation history
  statement {
    sid    = "DynamoDBHistory"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:Query",
      "dynamodb:GetItem",
    ]
    resources = [
      aws_dynamodb_table.conversations.arn,
      "${aws_dynamodb_table.conversations.arn}/index/*",
    ]
  }

  # DynamoDB SSE with a customer-managed CMK requires the caller to hold
  # these KMS permissions (DynamoDB uses the caller's credentials to
  # access the key per request).
  statement {
    sid    = "KMSForDynamoDB"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [local.security_tooling_kms_arn]
  }
}

resource "aws_iam_role_policy" "orchestrator" {
  provider = aws.security_tooling
  role     = aws_iam_role.orchestrator.id
  name     = "orchestrator"
  policy   = data.aws_iam_policy_document.orchestrator.json
}

resource "aws_cloudwatch_log_group" "orchestrator" {
  provider          = aws.security_tooling
  name              = "/aws/lambda/${var.project}-orchestrator"
  retention_in_days = 30
  kms_key_id        = local.security_tooling_kms_arn
}

resource "aws_lambda_function" "orchestrator" {
  provider = aws.security_tooling

  function_name    = "${var.project}-orchestrator"
  description      = "Chat API orchestrator: invokes the Bedrock agent, stores history"
  role             = aws_iam_role.orchestrator.arn
  runtime          = "python3.12"
  handler          = "lambda_function.handler"
  filename         = data.archive_file.orchestrator.output_path
  source_code_hash = data.archive_file.orchestrator.output_base64sha256
  timeout          = 120 # agent calls + cold-start retries can run long
  memory_size      = 256

  environment {
    variables = {
      AGENT_ID           = aws_bedrockagent_agent.analyst.agent_id
      AGENT_ALIAS_ID     = var.orchestrator_agent_alias_id
      CONVERSATION_TABLE = aws_dynamodb_table.conversations.name
      HISTORY_TTL_DAYS   = "30"
      MAX_RESUME_RETRIES = "3"
      LOG_LEVEL          = "INFO"
    }
  }

  depends_on = [
    aws_iam_role_policy.orchestrator,
    aws_cloudwatch_log_group.orchestrator,
  ]
}
