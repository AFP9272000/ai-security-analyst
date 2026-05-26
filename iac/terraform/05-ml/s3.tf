# Training data bucket (in Security Tooling)
#
# Pipeline reads raw CloudTrail data from here as the training channel
# input. Populated either by manual upload from Athena query results or
# by future automation that runs Athena queries on a schedule.

resource "aws_s3_bucket" "training_data" {
  provider = aws.security_tooling

  bucket        = "${var.project}-training-data-${local.security_tooling_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "training_data" {
  provider = aws.security_tooling

  bucket                  = aws_s3_bucket.training_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "training_data" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.training_data.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "training_data" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.training_data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.baseline_key_arns["security-tooling"]
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "training_data" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.training_data.arn, "${aws_s3_bucket.training_data.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "training_data" {
  provider = aws.security_tooling
  bucket   = aws_s3_bucket.training_data.id
  policy   = data.aws_iam_policy_document.training_data.json
}

# Model artifacts bucket (in Security Tooling)
#
# SageMaker writes trained model tarballs and pipeline outputs here.
# Versioned and KMS-encrypted; older versions expire after 90 days.

resource "aws_s3_bucket" "model_artifacts" {
  provider = aws.security_tooling

  bucket        = "${var.project}-model-artifacts-${local.security_tooling_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "model_artifacts" {
  provider = aws.security_tooling

  bucket                  = aws_s3_bucket.model_artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "model_artifacts" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.model_artifacts.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "model_artifacts" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.model_artifacts.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.baseline_key_arns["security-tooling"]
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "model_artifacts" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.model_artifacts.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }
}

data "aws_iam_policy_document" "model_artifacts" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.model_artifacts.arn, "${aws_s3_bucket.model_artifacts.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "model_artifacts" {
  provider = aws.security_tooling
  bucket   = aws_s3_bucket.model_artifacts.id
  policy   = data.aws_iam_policy_document.model_artifacts.json
}
