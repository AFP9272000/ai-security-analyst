# AWS Config
#
# Aggregator in security-tooling + per-account recorders that ship to a
# central S3 bucket in log-archive.
#
# REVISED v2: Drop explicit aws_iam_service_linked_role resources.
# AWSServiceRoleForConfig is auto-created in every member account when
# trusted access for config.amazonaws.com is enabled at the Org level
# (which happens in 01-foundation/org.tf). Recorders reference the SLR by
# its predictable ARN. `removed` blocks below clean up any SLR state that
# may have been recorded on a previous failed apply.

locals {
  # Predictable ARN for the auto-created service-linked role.
  config_slr_arn_template = "arn:aws:iam::%s:role/aws-service-role/config.amazonaws.com/AWSServiceRoleForConfig"
}

# Cleanup: remove any pre-existing SLR resources from state without deleting
# them in AWS. Safe whether or not they were ever in state.

removed {
  from = aws_iam_service_linked_role.config_mgmt
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_service_linked_role.config_log_archive
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_service_linked_role.config_security_tooling
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_iam_service_linked_role.config_workload
  lifecycle {
    destroy = false
  }
}

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
# Each account uses the predictable AWSServiceRoleForConfig SLR ARN.

# Management
resource "aws_config_configuration_recorder" "mgmt" {
  name     = "${var.project}-recorder"
  role_arn = format(local.config_slr_arn_template, local.mgmt_account_id)

  recording_group {
    all_supported                 = true
    include_global_resource_types = true
  }
}

resource "aws_config_delivery_channel" "mgmt" {
  name           = "${var.project}-delivery"
  s3_bucket_name = aws_s3_bucket.config_logs.id

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
resource "aws_config_configuration_recorder" "log_archive" {
  provider = aws.log_archive

  name     = "${var.project}-recorder"
  role_arn = format(local.config_slr_arn_template, local.log_archive_account_id)

  recording_group {
    all_supported                 = true
    include_global_resource_types = false
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
resource "aws_config_configuration_recorder" "security_tooling" {
  provider = aws.security_tooling

  name     = "${var.project}-recorder"
  role_arn = format(local.config_slr_arn_template, local.security_tooling_id)

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
resource "aws_config_configuration_recorder" "workload" {
  provider = aws.workload

  name     = "${var.project}-recorder"
  role_arn = format(local.config_slr_arn_template, local.workload_account_id)

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
