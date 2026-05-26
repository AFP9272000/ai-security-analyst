# SageMaker execution role (in Security Tooling)
#
# Trusted by sagemaker.amazonaws.com. Used by:
#   - Pipeline executions (preprocess, train, evaluate)
#   - Model registry
#   - Inference endpoints (Phase 5 Part 2)
#
# Permissions: scoped to the buckets and ECR repo this layer creates,
# plus standard SageMaker prerequisites.

data "aws_iam_policy_document" "sagemaker_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sagemaker.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "sagemaker_execution" {
  provider = aws.security_tooling

  name               = "${var.project}-sagemaker-execution"
  assume_role_policy = data.aws_iam_policy_document.sagemaker_assume.json
  description        = "Execution role for SageMaker pipelines, training jobs, and endpoints"
}

data "aws_iam_policy_document" "sagemaker_execution" {
  # S3: read training data, write model artifacts
  statement {
    sid    = "S3DataAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.training_data.arn,
      "${aws_s3_bucket.training_data.arn}/*",
      aws_s3_bucket.model_artifacts.arn,
      "${aws_s3_bucket.model_artifacts.arn}/*",
    ]
  }

  # ECR: pull the training/inference image
  statement {
    sid    = "ECRReadAccess"
    effect = "Allow"
    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
      "ecr:GetAuthorizationToken",
      "ecr:BatchCheckLayerAvailability",
    ]
    resources = ["*"]
  }

  # KMS: decrypt the training data and re-encrypt outputs
  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:GenerateDataKey",
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:CreateGrant",
    ]
    resources = [local.baseline_key_arns["security-tooling"]]
  }

  # CloudWatch Logs: write training logs
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/sagemaker/*",
    ]
  }

  # CloudWatch Metrics: training and endpoint metrics
  statement {
    sid    = "CloudWatchMetrics"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData",
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "cloudwatch:namespace"
      values   = ["/aws/sagemaker/*", "ai-sec-analyst/*"]
    }
  }

  # ECR private network access (for VPC-mode endpoints)
  statement {
    sid    = "VPCSupport"
    effect = "Allow"
    actions = [
      "ec2:CreateNetworkInterface",
      "ec2:CreateNetworkInterfacePermission",
      "ec2:DeleteNetworkInterface",
      "ec2:DeleteNetworkInterfacePermission",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeVpcs",
      "ec2:DescribeDhcpOptions",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sagemaker_execution" {
  provider = aws.security_tooling

  role   = aws_iam_role.sagemaker_execution.id
  name   = "sagemaker-execution"
  policy = data.aws_iam_policy_document.sagemaker_execution.json
}
