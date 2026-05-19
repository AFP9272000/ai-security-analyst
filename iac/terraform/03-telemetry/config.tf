# AWS Config
#
# Two parts:
# 1. Aggregator in Security Tooling (delegated admin), org-wide view of
#    config + compliance across all member accounts.
# 2. Per-account recorder + delivery channel deployed via CloudFormation
#    StackSet from Management (using the SERVICE_MANAGED model wired up in
#    foundation). Recorders ship logs to a central S3 bucket in the
#    log-archive account.
#
# The recorder configuration is fan-out: same template into every
# member-account, expressed as a CFN StackSet because that's the cleanest
# AWS-native multi-account pattern.

# Config aggregator (in Security Tooling)

resource "aws_config_configuration_aggregator" "org" {
  provider = aws.security_tooling

  name = "${var.project}-org-aggregator"

  organization_aggregation_source {
    all_regions = false
    regions     = [var.region]
    role_arn    = aws_iam_role.config_aggregator.arn
  }
}

resource "aws_iam_role" "config_aggregator" {
  provider = aws.security_tooling

  name = "${var.project}-config-aggregator"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "config.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "config_aggregator" {
  provider = aws.security_tooling

  role       = aws_iam_role.config_aggregator.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSConfigRoleForOrganizations"
}

# Config delivery S3 bucket (in log-archive)
#
# Separate bucket from the CloudTrail one. Config and CloudTrail have
# different file formats and lifecycle needs, and keeping them split
# means Athena queries don't need to filter junk.

resource "aws_s3_bucket" "config_logs" {
  provider = aws.log_archive

  bucket        = "${var.project}-config-logs-${local.log_archive_account_id}"
  force_destroy = true
}

resource "aws_s3_bucket_public_access_block" "config_logs" {
  provider = aws.log_archive

  bucket                  = aws_s3_bucket.config_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "config_logs" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "config_logs" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.baseline_key_arns["log-archive"]
    }
    bucket_key_enabled = true
  }
}

data "aws_iam_policy_document" "config_logs_bucket" {
  statement {
    sid    = "AWSConfigBucketPermissionsCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl", "s3:ListBucket"]
    resources = [aws_s3_bucket.config_logs.arn]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values = [
        local.mgmt_account_id,
        local.log_archive_account_id,
        local.security_tooling_id,
        local.workload_account_id,
      ]
    }
  }

  statement {
    sid    = "AWSConfigBucketDelivery"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["config.amazonaws.com"]
    }
    actions = ["s3:PutObject"]
    resources = [
      "${aws_s3_bucket.config_logs.arn}/AWSLogs/${local.mgmt_account_id}/Config/*",
      "${aws_s3_bucket.config_logs.arn}/AWSLogs/${local.log_archive_account_id}/Config/*",
      "${aws_s3_bucket.config_logs.arn}/AWSLogs/${local.security_tooling_id}/Config/*",
      "${aws_s3_bucket.config_logs.arn}/AWSLogs/${local.workload_account_id}/Config/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceAccount"
      values = [
        local.mgmt_account_id,
        local.log_archive_account_id,
        local.security_tooling_id,
        local.workload_account_id,
      ]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.config_logs.arn, "${aws_s3_bucket.config_logs.arn}/*"]
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

resource "aws_s3_bucket_policy" "config_logs" {
  provider = aws.log_archive

  bucket = aws_s3_bucket.config_logs.id
  policy = data.aws_iam_policy_document.config_logs_bucket.json
}

# Per-account Config recorder + delivery channel
#
# Each member account (plus management) gets the same configuration:
# - Service-linked role for Config
# - Recorder enabled for all resource types
# - Delivery channel writes to the shared bucket in log-archive
#
# Three resource pairs because TF doesn't loop providers.

# Management
resource "aws_iam_service_linked_role" "config_mgmt" {
  aws_service_name = "config.amazonaws.com"
  description      = "Service-linked role for AWS Config in Management"

  lifecycle {
    ignore_changes = [aws_service_name, description]
  }
}

resource "aws_config_configuration_recorder" "mgmt" {
  name     = "${var.project}-recorder"
  role_arn = aws_iam_service_linked_role.config_mgmt.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "mgmt" {
  name           = "${var.project}-delivery"
  s3_bucket_name = aws_s3_bucket.config_logs.id
  s3_key_prefix  = ""

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.mgmt]
}

resource "aws_config_configuration_recorder_status" "mgmt" {
  name       = aws_config_configuration_recorder.mgmt.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.mgmt]
}

# log-archive
resource "aws_iam_service_linked_role" "config_log_archive" {
  provider = aws.log_archive

  aws_service_name = "config.amazonaws.com"
  description      = "Service-linked role for AWS Config in log-archive"

  lifecycle {
    ignore_changes = [aws_service_name, description]
  }
}

resource "aws_config_configuration_recorder" "log_archive" {
  provider = aws.log_archive

  name     = "${var.project}-recorder"
  role_arn = aws_iam_service_linked_role.config_log_archive.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = false # global types only need to be recorded in one account
  }
}

resource "aws_config_delivery_channel" "log_archive" {
  provider = aws.log_archive

  name           = "${var.project}-delivery"
  s3_bucket_name = aws_s3_bucket.config_logs.id

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.log_archive]
}

resource "aws_config_configuration_recorder_status" "log_archive" {
  provider = aws.log_archive

  name       = aws_config_configuration_recorder.log_archive.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.log_archive]
}

# security-tooling
resource "aws_iam_service_linked_role" "config_security_tooling" {
  provider = aws.security_tooling

  aws_service_name = "config.amazonaws.com"
  description      = "Service-linked role for AWS Config in security-tooling"

  lifecycle {
    ignore_changes = [aws_service_name, description]
  }
}

resource "aws_config_configuration_recorder" "security_tooling" {
  provider = aws.security_tooling

  name     = "${var.project}-recorder"
  role_arn = aws_iam_service_linked_role.config_security_tooling.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = false
  }
}

resource "aws_config_delivery_channel" "security_tooling" {
  provider = aws.security_tooling

  name           = "${var.project}-delivery"
  s3_bucket_name = aws_s3_bucket.config_logs.id

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.security_tooling]
}

resource "aws_config_configuration_recorder_status" "security_tooling" {
  provider = aws.security_tooling

  name       = aws_config_configuration_recorder.security_tooling.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.security_tooling]
}

# workload
resource "aws_iam_service_linked_role" "config_workload" {
  provider = aws.workload

  aws_service_name = "config.amazonaws.com"
  description      = "Service-linked role for AWS Config in workload"

  lifecycle {
    ignore_changes = [aws_service_name, description]
  }
}

resource "aws_config_configuration_recorder" "workload" {
  provider = aws.workload

  name     = "${var.project}-recorder"
  role_arn = aws_iam_service_linked_role.config_workload.arn

  recording_group {
    all_supported                 = true
    include_global_resource_types = false
  }
}

resource "aws_config_delivery_channel" "workload" {
  provider = aws.workload

  name           = "${var.project}-delivery"
  s3_bucket_name = aws_s3_bucket.config_logs.id

  snapshot_delivery_properties {
    delivery_frequency = "TwentyFour_Hours"
  }

  depends_on = [aws_config_configuration_recorder.workload]
}

resource "aws_config_configuration_recorder_status" "workload" {
  provider = aws.workload

  name       = aws_config_configuration_recorder.workload.name
  is_enabled = true

  depends_on = [aws_config_delivery_channel.workload]
}
