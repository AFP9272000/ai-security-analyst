# KMS baseline (Phase 1.6)
#
# One general-purpose CMK per member account. Key policy grants kms:* to
# the account root, which lets account IAM policies further delegate. This
# matches AWS's default key policy pattern. Layer-specific keys
# (CloudTrail logs, enriched bucket, SageMaker, etc.) get tighter
# purpose-scoped policies in their own layers.
#
# Rotation enabled (annual, AWS-managed). Aliased
# alias/ai-sec-analyst-baseline for cross-account discoverability.

locals {
  baseline_key_alias = "alias/${var.project}-baseline"
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
