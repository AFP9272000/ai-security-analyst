# Enricher Lambda 
#
# Subscribes to the security-findings EventBridge bus, normalizes
# findings, writes enriched JSON to S3. See lambdas/enricher/ for code.
#
# Runs OUTSIDE the security-tooling VPC by design, see ADR-0010.

# Lambda package

data "archive_file" "enricher" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/enricher"
  output_path = "${path.module}/.build/enricher.zip"
  excludes = [
    "__pycache__",
    "*.pyc",
    "tests",
    ".pytest_cache",
    "README.md",
  ]
}

# IAM role + policy

data "aws_iam_policy_document" "enricher_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "enricher" {
  provider = aws.security_tooling

  name               = "${var.project}-enricher"
  assume_role_policy = data.aws_iam_policy_document.enricher_assume.json
  description        = "Execution role for the security findings enricher Lambda"
}

data "aws_iam_policy_document" "enricher_policy" {
  # CloudWatch Logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-enricher",
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-enricher:*",
    ]
  }

  # Write to the enriched-findings bucket
  statement {
    sid    = "S3WriteEnrichedFindings"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectTagging",
    ]
    resources = ["${aws_s3_bucket.enriched_findings.arn}/enriched/*"]
  }

  # KMS for S3 encryption
  statement {
    sid    = "KMSEncryptForS3"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [local.baseline_key_arns["security-tooling"]]
  }
}

resource "aws_iam_role_policy" "enricher" {
  provider = aws.security_tooling

  role   = aws_iam_role.enricher.id
  name   = "enricher-runtime"
  policy = data.aws_iam_policy_document.enricher_policy.json
}

# Log group (pre-create so we control retention + KMS)

resource "aws_cloudwatch_log_group" "enricher" {
  provider = aws.security_tooling

  name              = "/aws/lambda/${var.project}-enricher"
  retention_in_days = 30
  kms_key_id        = local.baseline_key_arns["security-tooling"]
}

# Lambda function

resource "aws_lambda_function" "enricher" {
  provider = aws.security_tooling

  function_name    = "${var.project}-enricher"
  description      = "Normalizes security findings from EventBridge and writes to S3"
  role             = aws_iam_role.enricher.arn
  runtime          = "python3.12"
  handler          = "lambda_function.handler"
  filename         = data.archive_file.enricher.output_path
  source_code_hash = data.archive_file.enricher.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      ENRICHED_BUCKET = aws_s3_bucket.enriched_findings.id
      ENVIRONMENT     = "prod"
      LOG_LEVEL       = "INFO"
    }
  }

  # Module-level globals are reused across warm invocations; ensure
  # changes to the package source trigger a real function update.
  depends_on = [
    aws_iam_role_policy.enricher,
    aws_cloudwatch_log_group.enricher,
  ]
}

# EventBridge subscription to the security-findings bus
#
# The bus lives in security-tooling (created in 03-telemetry). We subscribe
# the Lambda via a rule on the SAME account/bus, no cross-account
# EventBridge plumbing needed.

resource "aws_cloudwatch_event_rule" "enricher_subscription" {
  provider = aws.security_tooling

  name        = "${var.project}-enricher-subscription"
  description = "Triggers the enricher Lambda for all events on the security-findings bus"

  event_bus_name = data.terraform_remote_state.telemetry.outputs.security_findings_bus_name

  # Match all events on the custom bus.
  event_pattern = jsonencode({
    source = [{ exists = true }]
  })
}

resource "aws_cloudwatch_event_target" "enricher_target" {
  provider = aws.security_tooling

  rule           = aws_cloudwatch_event_rule.enricher_subscription.name
  event_bus_name = data.terraform_remote_state.telemetry.outputs.security_findings_bus_name
  arn            = aws_lambda_function.enricher.arn
  target_id      = "enricher"

  retry_policy {
    maximum_event_age_in_seconds = 3600
    maximum_retry_attempts       = 3
  }
}

resource "aws_lambda_permission" "enricher_eventbridge" {
  provider = aws.security_tooling

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.enricher.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.enricher_subscription.arn
}
