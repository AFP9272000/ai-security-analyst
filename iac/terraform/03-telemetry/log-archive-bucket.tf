# CloudTrail log archive bucket (in Log Archive account)

resource "aws_s3_bucket" "log_archive" {
  provider = aws.log_archive

  bucket              = "${var.project}-cloudtrail-logs-${local.log_archive_account_id}"
  object_lock_enabled = true

  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "log_archive" {
  provider = aws.log_archive

  bucket                  = aws_s3_bucket.log_archive.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "log_archive" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.log_archive.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_archive" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.log_archive.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.baseline_key_arns["log-archive"]
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_object_lock_configuration" "log_archive" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.log_archive.id

  rule {
    default_retention {
      mode = var.log_archive_object_lock_mode
      days = var.log_archive_retention_days
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "log_archive" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.log_archive.id

  rule {
    id     = "transition-to-cheaper-storage"
    status = "Enabled"

    filter {}

    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 180
      storage_class = "GLACIER_IR"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

# Bucket policy
#
# v3: write from org CloudTrail to both MGMT and orgID paths.
# v4: cross-account read grant for security-tooling so Athena
# and Glue running there can analyze the CloudTrail data.

data "aws_iam_policy_document" "log_archive_bucket" {
  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.log_archive.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${local.mgmt_account_id}:trail/${var.project}-org-trail"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.log_archive.arn}/AWSLogs/${local.mgmt_account_id}/*",
      "${aws_s3_bucket.log_archive.arn}/AWSLogs/${local.org_id}/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${var.region}:${local.mgmt_account_id}:trail/${var.project}-org-trail"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.mgmt_account_id]
    }
  }

  # Phase 4: cross-account read for security-tooling Athena/Glue
  statement {
    sid    = "AllowSecurityToolingAnalyticsRead"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.security_tooling_id}:root"]
    }
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]
    resources = ["${aws_s3_bucket.log_archive.arn}/*"]
  }

  statement {
    sid    = "AllowSecurityToolingAnalyticsList"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.security_tooling_id}:root"]
    }
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.log_archive.arn]
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.log_archive.arn, "${aws_s3_bucket.log_archive.arn}/*"]
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

resource "aws_s3_bucket_policy" "log_archive" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.log_archive.id
  policy = data.aws_iam_policy_document.log_archive_bucket.json
}
