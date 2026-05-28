# SageMaker execution role (in Security Tooling)
#
# Trusted by sagemaker.amazonaws.com. Used by:
#   - Pipeline executions (preprocess, train, evaluate, register)
#   - Model registry
#   - Inference endpoints
#
# NOTE ON SINGLE-ROLE PATTERN: the pipeline orchestration role and the
# job execution role are the same role (it passes itself to the jobs it
# creates). A hardened setup would separate these. Flagged for the
# end-of-project hardening ADR pass.

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
  # S3: read training data, write model artifacts (project buckets)
  statement {
    sid    = "S3ProjectBuckets"
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

  # SageMaker default session bucket. The Python SDK uploads step code
  # (preprocess.py, evaluate.py) and stages intermediate artifacts here
  # by default - bucket name pattern: sagemaker-<region>-<account>. The
  # execution role must read/write it for jobs to find their code. To
  # keep everything in project buckets instead, you'd override the SDK
  # Session default_bucket - deferred; granting access is the standard
  # pattern. This bucket uses SSE-S3 (AES256), so no KMS grant needed.
  statement {
    sid    = "S3SageMakerDefaultBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::sagemaker-${var.region}-${local.security_tooling_id}",
      "arn:aws:s3:::sagemaker-${var.region}-${local.security_tooling_id}/*",
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

  # KMS: decrypt project-bucket data and re-encrypt outputs (our CMK)
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

  # CloudWatch Logs: write training/processing logs
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

  # CloudWatch Metrics
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

  # ECR private network access (VPC-mode endpoints in Part 2)
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

  # PassRole: pipeline passes this role to the jobs it creates.
  statement {
    sid    = "PassRoleToSageMakerJobs"
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = [aws_iam_role.sagemaker_execution.arn]
    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["sagemaker.amazonaws.com"]
    }
  }

  # SageMaker job management: launch/monitor jobs, register packages.
  statement {
    sid    = "SageMakerJobManagement"
    effect = "Allow"
    actions = [
      "sagemaker:CreateProcessingJob",
      "sagemaker:DescribeProcessingJob",
      "sagemaker:StopProcessingJob",
      "sagemaker:CreateTrainingJob",
      "sagemaker:DescribeTrainingJob",
      "sagemaker:StopTrainingJob",
      "sagemaker:CreateModel",
      "sagemaker:DescribeModel",
      "sagemaker:DeleteModel",
      "sagemaker:CreateModelPackage",
      "sagemaker:DescribeModelPackage",
      "sagemaker:UpdateModelPackage",
      "sagemaker:ListModelPackages",
      "sagemaker:AddTags",
      "sagemaker:ListTags",
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
