resource "aws_organizations_policy" "deny_root" {
  name        = "${var.project}-deny-root"
  description = "Deny root user API calls (billing console still permitted via management)"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyRootUser"
      Effect   = "Deny"
      Action   = "*"
      Resource = "*"
      Condition = {
        StringLike = {
          "aws:PrincipalArn" = "arn:aws:iam::*:root"
        }
      }
    }]
  })
}

resource "aws_organizations_policy" "deny_regions" {
  name        = "${var.project}-deny-regions"
  description = "Restrict operations to allowed regions; global services exempted"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyRegions"
      Effect = "Deny"
      NotAction = [
        "iam:*",
        "organizations:*",
        "route53:*",
        "cloudfront:*",
        "support:*",
        "sts:*",
        "globalaccelerator:*",
        "wafv2:*",
        "waf:*",
        "shield:*",
        "s3:ListAllMyBuckets",
        "s3:GetAccountPublicAccessBlock",
        "s3:PutAccountPublicAccessBlock",
        "tag:*",
        "health:*",
        "trustedadvisor:*",
        "ce:*",
        "cur:*",
      ]
      Resource = "*"
      Condition = {
        StringNotEquals = {
          "aws:RequestedRegion" = var.allowed_regions
        }
      }
    }]
  })
}

resource "aws_organizations_policy" "deny_disable_security" {
  name        = "${var.project}-deny-disable-security"
  description = "Prevent disabling CloudTrail, GuardDuty, Config, Security Hub"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "DenyDisableSecurityServices"
      Effect = "Deny"
      Action = [
        "cloudtrail:DeleteTrail",
        "cloudtrail:PutEventSelectors",
        "cloudtrail:StopLogging",
        "cloudtrail:UpdateTrail",
        "guardduty:DeleteDetector",
        "guardduty:DisassociateFromMasterAccount",
        "guardduty:StopMonitoringMembers",
        "guardduty:UpdateDetector",
        "config:DeleteConfigRule",
        "config:DeleteConfigurationRecorder",
        "config:DeleteDeliveryChannel",
        "config:StopConfigurationRecorder",
        "securityhub:DeleteInvitations",
        "securityhub:DisableSecurityHub",
        "securityhub:DisassociateFromMasterAccount",
        "securityhub:DeleteMembers",
      ]
      Resource = "*"
    }]
  })
}

resource "aws_organizations_policy" "deny_leave_org" {
  name        = "${var.project}-deny-leave-org"
  description = "Prevent member accounts from leaving the Organization"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid      = "DenyLeaveOrg"
      Effect   = "Deny"
      Action   = "organizations:LeaveOrganization"
      Resource = "*"
    }]
  })
}

# Attach all SCPs to both OUs (4 policies x 2 OUs = 8 attachments)
locals {
  scp_attachments = {
    for pair in setproduct(
      ["deny_root", "deny_regions", "deny_disable_security", "deny_leave_org"],
      ["security", "workload"]
    ) :
    "${pair[0]}-${pair[1]}" => {
      policy_key = pair[0]
      ou_key     = pair[1]
    }
  }

  scp_policy_ids = {
    deny_root             = aws_organizations_policy.deny_root.id
    deny_regions          = aws_organizations_policy.deny_regions.id
    deny_disable_security = aws_organizations_policy.deny_disable_security.id
    deny_leave_org        = aws_organizations_policy.deny_leave_org.id
  }
}

resource "aws_organizations_policy_attachment" "this" {
  for_each = local.scp_attachments

  policy_id = local.scp_policy_ids[each.value.policy_key]
  target_id = local.ou_id_map[each.value.ou_key]
}
