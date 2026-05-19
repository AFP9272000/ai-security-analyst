# GuardDuty (configured in Security Tooling as delegated admin)
#
# Detector enabled. Org-level configuration auto-enables GuardDuty in
# every existing and future member account. Member accounts publish
# findings to the delegated admin's detector for a single pane of glass.
#
# NOTE v2: The detector was auto-created when foundation
# registered Security Tooling as the GuardDuty delegated administrator.
# We import that existing detector into state rather than creating a new
# one. Replace <DETECTOR_ID> below with the value from:
#   aws guardduty list-detectors --profile security-tooling --query 'DetectorIds[0]' --output text
#
# After a successful apply, the import block can be removed (state will
# already reflect the resource).

import {
  to = aws_guardduty_detector.main
  id = "<DETECTOR_ID>"
}

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

# Explicit member resources cover log-archive and workload immediately
# rather than waiting for the org-config reconciliation loop. Security
# Tooling is the admin so it doesn't need a self-pointing member.
resource "aws_guardduty_member" "log_archive" {
  provider = aws.security_tooling

  account_id  = local.log_archive_account_id
  detector_id = aws_guardduty_detector.main.id
  email       = "placeholder@example.com" # Required by API; ignored for org-managed members.
  invite      = false

  lifecycle {
    ignore_changes = [email]
  }
}

resource "aws_guardduty_member" "workload" {
  provider = aws.security_tooling

  account_id  = local.workload_account_id
  detector_id = aws_guardduty_detector.main.id
  email       = "placeholder@example.com"
  invite      = false

  lifecycle {
    ignore_changes = [email]
  }
}
