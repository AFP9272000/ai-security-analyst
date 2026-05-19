###############################################################################
# Security Hub (configured in Security Tooling as delegated admin)
#
# Like GuardDuty, the Security Hub instance was auto-created when
# foundation registered Security Tooling as the delegated admin. We
# import the existing aws_securityhub_account resource. After a
# successful apply, the import block can be removed.

import {
  to = aws_securityhub_account.main
  id = "834251004218 (this account)"
}

resource "aws_securityhub_account" "main" {
  provider = aws.security_tooling

  enable_default_standards = false # We subscribe to specific standards below for explicit control.
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls = true
}

# Org configuration: auto-enroll members

resource "aws_securityhub_organization_configuration" "main" {
  provider = aws.security_tooling

  auto_enable = true

  depends_on = [aws_securityhub_account.main]
}

# Standards subscriptions
#
# AWS Foundational Security Best Practices: the broadest default standard,
# covers IAM/EC2/S3/etc. CIS 2.0 is the second most popular for
# enterprise security baselines. PCI/HIPAA omitted, not applicable here.

data "aws_region" "current" {
  provider = aws.security_tooling
}

resource "aws_securityhub_standards_subscription" "afsbp" {
  provider = aws.security_tooling

  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.main]
}

resource "aws_securityhub_standards_subscription" "cis" {
  provider = aws.security_tooling

  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"

  depends_on = [aws_securityhub_account.main]
}

# Member account enrollment

resource "aws_securityhub_member" "log_archive" {
  provider = aws.security_tooling

  account_id = local.log_archive_account_id
  email      = "placeholder@example.com" # Required by API; ignored for org-managed members.
  invite     = false

  depends_on = [aws_securityhub_account.main]

  lifecycle {
    ignore_changes = [email]
  }
}

resource "aws_securityhub_member" "workload" {
  provider = aws.security_tooling

  account_id = local.workload_account_id
  email      = "placeholder@example.com"
  invite     = false

  depends_on = [aws_securityhub_account.main]

  lifecycle {
    ignore_changes = [email]
  }
}
