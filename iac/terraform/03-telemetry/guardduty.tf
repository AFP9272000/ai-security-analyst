# GuardDuty (configured in Security Tooling as delegated admin)
#
# Detector + org configuration only. Member account enrollment is handled
# entirely by auto_enable_organization_members = "ALL" on the org config.
#
# REVISED v2: Removed explicit aws_guardduty_member resources.
# With org auto-enable on, AWS manages member enrollment automatically;
# the explicit resources conflicted with that auto-management and
# triggered DisassociateMembers errors on apply. The `removed` blocks
# below clean those resources out of state without disassociating them
# in AWS, the org config continues to keep them enrolled.

removed {
  from = aws_guardduty_member.log_archive
  lifecycle {
    destroy = false
  }
}

removed {
  from = aws_guardduty_member.workload
  lifecycle {
    destroy = false
  }
}

# Detector (already in state from import; no import block needed)

resource "aws_guardduty_detector" "main" {
  provider = aws.security_tooling

  enable                       = true
  finding_publishing_frequency = var.guardduty_finding_frequency

  datasources {
    s3_logs {
      enable = true
    }
    kubernetes {
      audit_logs {
        enable = false # No EKS in this project.
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          enable = false # Avoids per-scan charges; phase-9 attack sims can re-enable.
        }
      }
    }
  }
}

resource "aws_guardduty_organization_configuration" "main" {
  provider = aws.security_tooling

  detector_id                      = aws_guardduty_detector.main.id
  auto_enable_organization_members = "ALL"

  datasources {
    s3_logs {
      auto_enable = true
    }
    kubernetes {
      audit_logs {
        enable = false
      }
    }
    malware_protection {
      scan_ec2_instance_with_findings {
        ebs_volumes {
          auto_enable = false
        }
      }
    }
  }
}
