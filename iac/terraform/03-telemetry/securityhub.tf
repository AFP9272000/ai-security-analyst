# Security Hub (configured in Security Tooling as delegated admin)
#
# REVISED v2:
# - Removed explicit aws_securityhub_member resources. With
#   auto_enable = true on the org configuration, AWS auto-manages member
#   enrollment. The explicit resources conflicted and triggered
#   DeleteMembers errors (which the SCP correctly blocks).
# - Added 15-minute create timeout on standards subscriptions. AWS
#   regularly takes 4-10 minutes to mark them READY, and the default
#   3-minute Terraform wait is too short.
#
# The import block stays for first-time state landing of
# aws_securityhub_account.main (which was auto-created by foundation's
# delegated admin registration). Replace <ACCOUNT_ID> with the
# Security Tooling account ID. After a successful apply, the import
# block can be removed.


removed {
  from = aws_securityhub_member.log_archive
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_securityhub_member.workload
  lifecycle {
    destroy = false
  }
}

import {
  to = aws_securityhub_account.main
  id = "834251004218"
}

resource "aws_securityhub_account" "main" {
  provider = aws.security_tooling

  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true
}

# Org configuration auto-enroll members

resource "aws_securityhub_organization_configuration" "main" {
  provider = aws.security_tooling

  auto_enable = true

  depends_on = [aws_securityhub_account.main]
}

# Standards subscriptions

data "aws_region" "current" {
  provider = aws.security_tooling
}

resource "aws_securityhub_standards_subscription" "afsbp" {
  provider = aws.security_tooling

  standards_arn = "arn:aws:securityhub:${data.aws_region.current.name}::standards/aws-foundational-security-best-practices/v/1.0.0"

  depends_on = [aws_securityhub_account.main]

  timeouts {
    create = "25m"
  }
}

resource "aws_securityhub_standards_subscription" "cis" {
  provider = aws.security_tooling

  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"

  depends_on = [aws_securityhub_account.main]

  timeouts {
    create = "25m"
  }
}
