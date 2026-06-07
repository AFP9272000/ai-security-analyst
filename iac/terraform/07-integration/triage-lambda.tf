# Triage Lambda (in Security Tooling)
#
# Invoked by the EventBridge rules in alerting.tf. Parses the finding,
# dedups by finding id, optionally triages it with the agent, publishes
# the alert to SNS (and optionally Slack). Not in a VPC.

data "archive_file" "triage" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/triage"
  output_path = "${path.module}/.build/triage.zip"
  excludes    = ["__pycache__", "*.pyc", "README.md", "requirements.txt"]
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "triage" {
  provider           = aws.security_tooling
  name               = "${var.project}-triage"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  description        = "Execution role for the event-driven triage Lambda"
}

data "aws_iam_policy_document" "triage" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-triage",
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-triage:*",
    ]
  }

  statement {
    sid       = "PublishAlerts"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
  }

  # Dedup table: claim (PutItem) and release-on-failure (DeleteItem).
  statement {
    sid    = "DedupTable"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
    ]
    resources = [aws_dynamodb_table.alert_dedup.arn]
  }

  # Invoke the agent for triage. Authorized against the agent-alias ARN;
  # allow any alias of this agent (covers TSTALIASID and a published one).
  statement {
    sid    = "InvokeAgent"
    effect = "Allow"
    actions = [
      "bedrock:InvokeAgent",
    ]
    resources = [
      "arn:aws:bedrock:${var.region}:${local.security_tooling_id}:agent-alias/${local.agent_id}/*",
    ]
  }

  # Read the optional Slack webhook (SecureString) from SSM.
  statement {
    sid    = "ReadSlackWebhook"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
    ]
    resources = [
      "arn:aws:ssm:${var.region}:${local.security_tooling_id}:parameter/${var.project}/*",
    ]
  }

  # KMS: decrypt the log-group CMK, the SecureString SSM parameter, and
  # the CMK-encrypted dedup table (all the baseline key). SNS uses the
  # AWS-managed key, so no grant needed for publishing.
  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [local.security_tooling_kms_arn]
  }
}

resource "aws_iam_role_policy" "triage" {
  provider = aws.security_tooling
  role     = aws_iam_role.triage.id
  name     = "triage"
  policy   = data.aws_iam_policy_document.triage.json
}

resource "aws_cloudwatch_log_group" "triage" {
  provider          = aws.security_tooling
  name              = "/aws/lambda/${var.project}-triage"
  retention_in_days = 30
  kms_key_id        = local.security_tooling_kms_arn
}

resource "aws_lambda_function" "triage" {
  provider = aws.security_tooling

  function_name    = "${var.project}-triage"
  description      = "Auto-triages high-severity findings with the agent, alerts via SNS/Slack (deduped)"
  role             = aws_iam_role.triage.arn
  runtime          = "python3.12"
  handler          = "lambda_function.handler"
  filename         = data.archive_file.triage.output_path
  source_code_hash = data.archive_file.triage.output_base64sha256
  timeout          = 120 # agent triage + cold-start retries can run long
  memory_size      = 256

  environment {
    variables = {
      SNS_TOPIC_ARN       = aws_sns_topic.alerts.arn
      AGENT_ID            = local.agent_id
      AGENT_ALIAS_ID      = var.agent_alias_id
      ENABLE_AGENT_TRIAGE = tostring(var.enable_agent_triage)
      DEDUP_TABLE         = aws_dynamodb_table.alert_dedup.name
      DEDUP_TTL_HOURS     = tostring(var.dedup_ttl_hours)
      SLACK_WEBHOOK_PARAM = var.slack_webhook_ssm_param
      MAX_RESUME_RETRIES  = "5"
      LOG_LEVEL           = "INFO"
    }
  }

  depends_on = [
    aws_iam_role_policy.triage,
    aws_cloudwatch_log_group.triage,
  ]
}
