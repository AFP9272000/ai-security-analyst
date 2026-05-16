# KMS baseline
#
# One general-purpose CMK per member account. Key policy grants:
#   - Account root: kms:* (delegates further via IAM policies)
#   - CloudWatch Logs service: encrypt/decrypt log groups in this account
#   - CloudTrail service: encrypt/decrypt trails delivered to this account
#
# Layer-specific keys ship with their own layers using tighter policies.
#
# Rotation enabled (annual). Aliased alias/ai-sec-analyst-baseline.

locals {
  baseline_key_alias = "alias/${var.project}-baseline"
}

# Reusable statement generators - keeps the per-account data sources DRY

# CloudWatch Logs needs the service principal AND a condition scoping to
# the account's log groups. The service principal is region-specific.
locals {
  cw_logs_actions = [
    "kms:Encrypt*",
    "kms:Decrypt*",
    "kms:ReEncrypt*",
    "kms:GenerateDataKey*",
    "kms:DescribeKey",
  ]

  cloudtrail_actions = [
    "kms:GenerateDataKey*",
    "kms:DescribeKey",
    "kms:Decrypt",
  ]
}

# log-archive

data "aws_iam_policy_document" "baseline_log_archive" {
  provider = aws.log_archive

  statement {
    sid    = "EnableAccountRoot"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${aws_organizations_account.members["log-archive"].id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    actions   = local.cw_logs_actions
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.region}:${aws_organizations_account.members["log-archive"].id}:log-group:*"]
    }
  }

  statement {
    sid    = "AllowCloudTrail"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = local.cloudtrail_actions
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [aws_organizations_organization.this.master_account_id]
    }
  }
}

resource "aws_kms_key" "baseline_log_archive" {
  provider = aws.log_archive

  description              = "Baseline CMK for ${var.project} log-archive account"
  enable_key_rotation      = true
  deletion_window_in_days  = 30
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"

  policy = data.aws_iam_policy_document.baseline_log_archive.json
}

resource "aws_kms_alias" "baseline_log_archive" {
  provider      = aws.log_archive
  name          = local.baseline_key_alias
  target_key_id = aws_kms_key.baseline_log_archive.key_id
}

# security-tooling

data "aws_iam_policy_document" "baseline_security_tooling" {
  provider = aws.security_tooling

  statement {
    sid    = "EnableAccountRoot"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${aws_organizations_account.members["security-tooling"].id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    actions   = local.cw_logs_actions
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.region}:${aws_organizations_account.members["security-tooling"].id}:log-group:*"]
    }
  }

  statement {
    sid    = "AllowCloudTrail"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = local.cloudtrail_actions
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [aws_organizations_organization.this.master_account_id]
    }
  }
}

resource "aws_kms_key" "baseline_security_tooling" {
  provider = aws.security_tooling

  description              = "Baseline CMK for ${var.project} security-tooling account"
  enable_key_rotation      = true
  deletion_window_in_days  = 30
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"

  policy = data.aws_iam_policy_document.baseline_security_tooling.json
}

resource "aws_kms_alias" "baseline_security_tooling" {
  provider      = aws.security_tooling
  name          = local.baseline_key_alias
  target_key_id = aws_kms_key.baseline_security_tooling.key_id
}

# workload

data "aws_iam_policy_document" "baseline_workload" {
  provider = aws.workload

  statement {
    sid    = "EnableAccountRoot"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${aws_organizations_account.members["workload"].id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${var.region}.amazonaws.com"]
    }
    actions   = local.cw_logs_actions
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${var.region}:${aws_organizations_account.members["workload"].id}:log-group:*"]
    }
  }

  statement {
    sid    = "AllowCloudTrail"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = local.cloudtrail_actions
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [aws_organizations_organization.this.master_account_id]
    }
  }
}

resource "aws_kms_key" "baseline_workload" {
  provider = aws.workload

  description              = "Baseline CMK for ${var.project} workload account"
  enable_key_rotation      = true
  deletion_window_in_days  = 30
  key_usage                = "ENCRYPT_DECRYPT"
  customer_master_key_spec = "SYMMETRIC_DEFAULT"

  policy = data.aws_iam_policy_document.baseline_workload.json
}

resource "aws_kms_alias" "baseline_workload" {
  provider      = aws.workload
  name          = local.baseline_key_alias
  target_key_id = aws_kms_key.baseline_workload.key_id
}
