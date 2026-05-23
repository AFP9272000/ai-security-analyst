# Enriched findings bucket (in Security Tooling)
#
# Destination for the enricher Lambda's output. Each
# enriched finding lands as a JSON object at:
#   enriched/<source>/<year>/<month>/<day>/<finding-id>.json
#
# Versioned, KMS-encrypted, TLS-only. Lifecycle to Glacier-IR after
# 90 days; the AI agent in Phase 6 queries recent findings (typically
# last 7-30 days), so older findings rarely need warm storage.

resource "aws_s3_bucket" "enriched_findings" {
  provider = aws.security_tooling

  bucket        = "${var.project}-enriched-findings-${local.security_tooling_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "enriched_findings" {
  provider = aws.security_tooling

  bucket                  = aws_s3_bucket.enriched_findings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "enriched_findings" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.enriched_findings.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "enriched_findings" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.enriched_findings.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.baseline_key_arns["security-tooling"]
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "enriched_findings" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.enriched_findings.id

  rule {
    id     = "transition-old-findings"
    status = "Enabled"

    filter {}

    transition {
      days          = var.enriched_findings_retention_days
      storage_class = "GLACIER_IR"
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

data "aws_iam_policy_document" "enriched_findings_bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.enriched_findings.arn, "${aws_s3_bucket.enriched_findings.arn}/*"]
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

resource "aws_s3_bucket_policy" "enriched_findings" {
  provider = aws.security_tooling

  bucket = aws_s3_bucket.enriched_findings.id
  policy = data.aws_iam_policy_document.enriched_findings_bucket.json
}

# Glue table for enriched findings (Lambda writes here)
#
# Layout: enriched/<source>/<year>/<month>/<day>/*.json
# Partitions projected on source, year, month, day.

resource "aws_glue_catalog_table" "enriched_findings" {
  provider = aws.security_tooling

  database_name = aws_glue_catalog_database.security.name
  name          = "enriched_findings"
  description   = "Lambda-enriched findings"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"                       = "TRUE"
    "classification"                 = "json"
    "projection.enabled"             = "true"
    "projection.source.type"         = "enum"
    "projection.source.values"       = "guardduty,securityhub,custom"
    "projection.year.type"           = "integer"
    "projection.year.range"          = "2024,2030"
    "projection.month.type"          = "integer"
    "projection.month.range"         = "1,12"
    "projection.month.digits"        = "2"
    "projection.day.type"            = "integer"
    "projection.day.range"           = "1,31"
    "projection.day.digits"          = "2"
    "storage.location.template"      = "s3://${aws_s3_bucket.enriched_findings.id}/enriched/$${source}/$${year}/$${month}/$${day}/"
  }

  partition_keys {
    name = "source"
    type = "string"
  }
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${aws_s3_bucket.enriched_findings.id}/enriched/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    compressed    = false

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    # Enriched finding schema - intentionally minimal here. The Lambda
    # in Phase 4 Part 2 defines the canonical shape; this table can be
    # updated to add columns as the enricher's output evolves.
    columns {
      name = "finding_id"
      type = "string"
    }
    columns {
      name = "source"
      type = "string"
    }
    columns {
      name = "detail_type"
      type = "string"
    }
    columns {
      name = "severity"
      type = "string"
    }
    columns {
      name = "account_id"
      type = "string"
    }
    columns {
      name = "region"
      type = "string"
    }
    columns {
      name = "resource_arn"
      type = "string"
    }
    columns {
      name = "resource_tags"
      type = "map<string,string>"
    }
    columns {
      name = "raw_detail"
      type = "string"
    }
    columns {
      name = "enriched_at"
      type = "string"
    }
  }
}
