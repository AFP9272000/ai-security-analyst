# Athena (in Security Tooling)
#
# Workgroup with KMS-encrypted query results in a dedicated S3 bucket.
# Workgroup enforces:
#   - All queries write to the configured location (override prevented)
#   - Query results encrypted with the security-tooling baseline CMK
#   - CloudWatch metrics published
#
# Query result bucket is separate from enriched findings; results are
# regeneratable, so a tight lifecycle is fine.

resource "aws_s3_bucket" "athena_results" {
  provider = aws.security_tooling

  bucket        = "${var.project}-athena-results-${local.security_tooling_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  provider = aws.security_tooling

  bucket                  = aws_s3_bucket.athena_results.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "athena_results" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.athena_results.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.athena_results.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.baseline_key_arns["security-tooling"]
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "athena_results" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.athena_results.id

  rule {
    id     = "expire-query-results"
    status = "Enabled"

    filter {}

    expiration {
      days = var.athena_results_lifecycle_days
    }

    noncurrent_version_expiration {
      noncurrent_days = 1
    }
  }
}

data "aws_iam_policy_document" "athena_results_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.athena_results.arn, "${aws_s3_bucket.athena_results.arn}/*"]
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

resource "aws_s3_bucket_policy" "athena_results" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.athena_results.id
  policy = data.aws_iam_policy_document.athena_results_bucket.json
}

# Workgroup

resource "aws_athena_workgroup" "security" {
  provider = aws.security_tooling

  name          = "${var.project}-security"
  description   = "Security analytics: queries against CloudTrail, GuardDuty, and enriched findings"
  state         = "ENABLED"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.id}/query-results/"

      encryption_configuration {
        encryption_option = "SSE_KMS"
        kms_key_arn       = local.baseline_key_arns["security-tooling"]
      }
    }

    engine_version {
      selected_engine_version = "AUTO"
    }

    # Bytes scanned per query - cost guardrail
    bytes_scanned_cutoff_per_query = 10737418240 # 10 GB
  }
}
