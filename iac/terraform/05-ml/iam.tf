# SageMaker execution role (in Security Tooling)
#
# Trusted by sagemaker.amazonaws.com. Used by:
#   - Pipeline executions (preprocess, train, evaluate, register)
#   - Model registry
#   - Inference endpoints
#
# Permissions: scoped to the buckets and ECR repo this layer creates,
# plus the SageMaker job-management + PassRole actions a pipeline needs
# to launch its sub-jobs.
#
# NOTE ON SINGLE-ROLE PATTERN: the pipeline orchestration role and the
# job execution role are the same role here (it passes itself to the
# jobs it creates). A hardened production setup would separate these -
# a thin orchestration role that can only PassRole a distinct, minimal
# job role. Single-role is the common tutorial pattern and acceptable
# for this portfolio account. Flagged for the end-of-project hardening
# ADR pass.

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

  # ECR private network access (for VPC-mode endpoints in Part 2)
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

  # PassRole: the pipeline passes this role to the processing/training
  # jobs it creates. The iam:PassedToService condition restricts the
  # pass to SageMaker only - prevents this from being a general-purpose
  # privilege-escalation grant.
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

  # SageMaker job management: the pipeline launches and monitors
  # processing jobs, training jobs, and registers model packages.
  # Resources are "*" because most Create* actions reference a
  # not-yet-created resource; scoping by name pattern is deferred to
  # the hardening pass. This is a single-purpose account.
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
