# Security Hub (configured in Security Tooling as delegated admin)
#
# REVISED v3:
# - Standards subscriptions (AFSBP, CIS) intentionally removed. See
#   docs/adr/0008-skip-security-hub-standards.md for the rationale.
# - The Security Hub Hub itself, org configuration, and the EventBridge
#   integration are all retained, so findings still flow.
#
# Members: auto-enrolled via org config. Standards subscriptions: skipped.
# The Hub is operational; controls subscriptions can be added later via
# central configuration once the Config SLR situation is fully resolved
# across all member accounts.

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

removed {
  from = aws_securityhub_standards_subscription.afsbp
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_securityhub_standards_subscription.cis
  lifecycle {
    destroy = false
  }
}

# Hub itself (already in state from import)

resource "aws_securityhub_account" "main" {
  provider = aws.security_tooling

  enable_default_standards  = false
  control_finding_generator = "SECURITY_CONTROL"
  auto_enable_controls      = true
}

# Org configuration, auto-enroll members

resource "aws_securityhub_organization_configuration" "main" {
  provider = aws.security_tooling

  auto_enable           = true
  auto_enable_standards = "NONE" # We're not using standards; don't auto-enable in new accounts either.

  depends_on = [aws_securityhub_account.main]
}
