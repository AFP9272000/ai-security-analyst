# Inference Lambda
#
# In-VPC (security-tooling private subnets) so it can reach the SageMaker
# endpoint via the sagemaker.runtime VPC interface endpoint. Hard
# dependency on 02-network being deployed.
#
# Deployment package built by archive_file in this layer (workflow
# uploads .build/ alongside tfplan; see ADR-0012 for the Lambda outside-
# VPC vs in-VPC rationale).

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

# AWS-managed VPC execution permissions
resource "aws_iam_role_policy_attachment" "inference_vpc" {
  provider = aws.security_tooling

  role       = aws_iam_role.inference.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "inference_policy" {
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
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-inference",
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-inference:*",
    ]
  }

  # SQS consume from inference queue
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

  # S3 read enriched findings + write scored findings (same bucket, different prefixes)
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

  # KMS for both read and write
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

  # SageMaker endpoint invocation
  statement {
    sid    = "SageMakerInvoke"
    effect = "Allow"
    actions = [
      "sagemaker:InvokeEndpoint",
    ]
    # Endpoint ARN is constructed even if endpoint_enabled = false; the
    # Lambda just fails at runtime in that case.
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

  # VPC config - required for reaching the SageMaker endpoint
  vpc_config {
    subnet_ids         = local.security_tooling_vpc_subnets
    security_group_ids = [local.security_tooling_endpoint_sg]
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
