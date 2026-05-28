# Inference Lambda
#
# Triggered by SQS (S3 -> SQS -> Lambda) when the enricher writes an
# enriched finding. Calls the SageMaker endpoint, writes scored findings.
#
# VPC config is GATED on endpoint_enabled (Phase 5 Part 2 v3 fix):
#   - endpoint_enabled = true  -> Lambda runs in-VPC to reach the endpoint
#   - endpoint_enabled = false -> Lambda runs outside VPC (no ENIs)
#
# Why: a VPC-attached Lambda provisions ENIs in the private subnets.
# Those ENIs block 02-network teardown for up to 45 min (AWS lazy reaper).
# When there's no endpoint to reach, there's no reason to be in-VPC, so
# we drop the VPC config and avoid the teardown hang entirely. See
# ADR-0012 (updated).
#
# Behavior when endpoint_enabled = false and a finding arrives: the
# Lambda fires, calls invoke_endpoint, gets a clean "endpoint not found"
# error (fail-fast), retries 3x, then the message lands in the DLQ.
# No network timeout, no hang.

data "archive_file" "inference" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/inference"
  output_path = "${path.module}/.build/inference.zip"
  excludes = [
    "__pycache__",
    "*.pyc",
    "tests",
    ".pytest_cache",
    "README.md",
  ]
}

# IAM

data "aws_iam_policy_document" "inference_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "inference" {
  provider = aws.security_tooling

  name               = "${var.project}-inference"
  assume_role_policy = data.aws_iam_policy_document.inference_assume.json
  description        = "Execution role for the inference Lambda"
}

# AWS-managed VPC execution permissions. Attached unconditionally it's
# harmless when the Lambda isn't in-VPC, and avoids a
# attach/detach churn cycle every time endpoint_enabled flips.
resource "aws_iam_role_policy_attachment" "inference_vpc" {
  provider = aws.security_tooling

  role       = aws_iam_role.inference.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "inference_policy" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-inference",
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-inference:*",
    ]
  }

  statement {
    sid    = "SQSConsume"
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [aws_sqs_queue.inference.arn]
  }

  statement {
    sid    = "S3ReadEnriched"
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = ["${local.enriched_findings_bucket_arn}/enriched/*"]
  }

  statement {
    sid    = "S3WriteScored"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:PutObjectTagging",
    ]
    resources = ["${local.enriched_findings_bucket_arn}/scored/*"]
  }

  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [local.baseline_key_arns["security-tooling"]]
  }

  statement {
    sid    = "SageMakerInvoke"
    effect = "Allow"
    actions = [
      "sagemaker:InvokeEndpoint",
    ]
    resources = [
      "arn:aws:sagemaker:${var.region}:${local.security_tooling_id}:endpoint/${var.project}-anomaly-endpoint",
    ]
  }
}

resource "aws_iam_role_policy" "inference" {
  provider = aws.security_tooling

  role   = aws_iam_role.inference.id
  name   = "inference-runtime"
  policy = data.aws_iam_policy_document.inference_policy.json
}

# Log group

resource "aws_cloudwatch_log_group" "inference" {
  provider = aws.security_tooling

  name              = "/aws/lambda/${var.project}-inference"
  retention_in_days = 30
  kms_key_id        = local.baseline_key_arns["security-tooling"]
}

# Lambda function

resource "aws_lambda_function" "inference" {
  provider = aws.security_tooling

  function_name    = "${var.project}-inference"
  description      = "Scores enriched security findings via the SageMaker anomaly endpoint"
  role             = aws_iam_role.inference.arn
  runtime          = "python3.12"
  handler          = "lambda_function.handler"
  filename         = data.archive_file.inference.output_path
  source_code_hash = data.archive_file.inference.output_base64sha256
  timeout          = var.inference_lambda_timeout
  memory_size      = 512

  environment {
    variables = {
      SCORED_BUCKET      = local.enriched_findings_bucket
      SAGEMAKER_ENDPOINT = "${var.project}-anomaly-endpoint"
      ENVIRONMENT        = "prod"
      LOG_LEVEL          = "INFO"
    }
  }

  # VPC config only when the endpoint exists. When endpoint_enabled =
  # false, no vpc_config block is rendered -> Lambda runs outside VPC ->
  # no ENIs -> Phase 2 can be torn down without a 45-min ENI hang.
  dynamic "vpc_config" {
    for_each = var.endpoint_enabled ? [1] : []
    content {
      subnet_ids         = local.security_tooling_vpc_subnets
      security_group_ids = [local.security_tooling_endpoint_sg]
    }
  }

  depends_on = [
    aws_iam_role_policy.inference,
    aws_iam_role_policy_attachment.inference_vpc,
    aws_cloudwatch_log_group.inference,
  ]
}

# Event source mapping: SQS -> Lambda

resource "aws_lambda_event_source_mapping" "inference_sqs" {
  provider = aws.security_tooling

  event_source_arn = aws_sqs_queue.inference.arn
  function_name    = aws_lambda_function.inference.arn

  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 10
  }
}
