# Tag policies
#
# Detection-mode tag policy enforcing the project's mandatory tag standard.
# Attached at the Org root so it applies to every member account.
#
# Detection vs enforcement:
#   - This policy validates tag keys exist with correct case + correct values
#     where enumerated. Non-compliance is REPORTED (visible in Resource Groups
#     Tagging API and AWS Config) but NOT blocked.
#   - To block resource creation on non-compliance, add the
#     "enforced_for" key listing AWS resource types (e.g. "ec2:instance,
#     s3:bucket"). Intentionally omitted for flexibility.
#
# Note: TAG_POLICY policy type was already enabled in org.tf via
# enabled_policy_types. This file only creates and attaches the policy.

resource "aws_organizations_policy" "mandatory_tags" {
  name        = "${var.project}-mandatory-tags"
  description = "Mandatory tag standard for ${var.project} resources (detection mode)"
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = {
      Project = {
        tag_key = {
          "@@assign" = "Project"
        }
        tag_value = {
          "@@assign" = [var.project]
        }
      }
      Layer = {
        tag_key = {
          "@@assign" = "Layer"
        }
        tag_value = {
          "@@assign" = [
            "00-bootstrap",
            "01-foundation",
            "02-network",
            "03-telemetry",
            "04-data",
            "05-ml",
            "06-genai",
            "07-workload",
          ]
        }
      }
      ManagedBy = {
        tag_key = {
          "@@assign" = "ManagedBy"
        }
        tag_value = {
          "@@assign" = [
            "terraform",
            "cloudformation",
            "bootstrap-script",
          ]
        }
      }
      Environment = {
        tag_key = {
          "@@assign" = "Environment"
        }
        tag_value = {
          "@@assign" = ["prod"]
        }
      }
      CostCenter = {
        tag_key = {
          "@@assign" = "CostCenter"
        }
        tag_value = {
          "@@assign" = ["portfolio"]
        }
      }
    }
  })

  depends_on = [aws_organizations_organization.this]
}

# Attach to the Org root so it applies to every account, including any
# accounts later moved out of the Security/Workload OUs.
resource "aws_organizations_policy_attachment" "mandatory_tags_root" {
  policy_id = aws_organizations_policy.mandatory_tags.id
  target_id = aws_organizations_organization.this.roots[0].id
}
