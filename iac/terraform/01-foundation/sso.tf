# IAM Identity Center (formerly AWS SSO)
#
# Prerequisite: Identity Center must be enabled in the AWS Console first.
# This Terraform manages permission sets, the Identity Store user/group,
# and account assignments. It does NOT enable the service itself.

data "aws_ssoadmin_instances" "this" {}

locals {
  sso_instance_arn   = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  sso_identity_store = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]

  # All AWS accounts that should receive the AdminAccess permission set:
  # Management plus the 3 member accounts we created earlier.
  all_account_ids = merge(
    { management = aws_organizations_organization.this.master_account_id },
    { for k, v in aws_organizations_account.members : k => v.id },
  )

  permission_sets = {
    admin = {
      name             = "AdminAccess"
      description      = "Full administrative access"
      session_duration = "PT8H"
      managed_policy   = "arn:aws:iam::aws:policy/AdministratorAccess"
    }
    poweruser = {
      name             = "PowerUserAccess"
      description      = "Power user access (no IAM management)"
      session_duration = "PT4H"
      managed_policy   = "arn:aws:iam::aws:policy/PowerUserAccess"
    }
    readonly = {
      name             = "ReadOnlyAccess"
      description      = "Read-only access"
      session_duration = "PT4H"
      managed_policy   = "arn:aws:iam::aws:policy/ReadOnlyAccess"
    }
  }
}

# Permission sets

resource "aws_ssoadmin_permission_set" "this" {
  for_each = local.permission_sets

  instance_arn     = local.sso_instance_arn
  name             = each.value.name
  description      = each.value.description
  session_duration = each.value.session_duration

  tags = local.common_tags
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each = local.permission_sets

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  managed_policy_arn = each.value.managed_policy
}

# Identity Store: user + group + membership

resource "aws_identitystore_user" "admin" {
  identity_store_id = local.sso_identity_store

  display_name = var.sso_display_name
  user_name    = var.sso_username

  name {
    given_name  = var.sso_given_name
    family_name = var.sso_family_name
  }

  emails {
    value   = var.root_email
    primary = true
  }
}

resource "aws_identitystore_group" "admins" {
  identity_store_id = local.sso_identity_store
  display_name      = "Administrators"
  description       = "Full administrative access across all org accounts"
}

resource "aws_identitystore_group_membership" "admin" {
  identity_store_id = local.sso_identity_store
  group_id          = aws_identitystore_group.admins.group_id
  member_id         = aws_identitystore_user.admin.user_id
}

# Account assignments: Administrators group -> AdminAccess -> every account

resource "aws_ssoadmin_account_assignment" "admin_to_all" {
  for_each = local.all_account_ids

  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this["admin"].arn

  principal_id   = aws_identitystore_group.admins.group_id
  principal_type = "GROUP"

  target_id   = each.value
  target_type = "AWS_ACCOUNT"

  # Avoid the race condition that bit with SCPs: ensure managed policies
  # are attached and group membership exists before the assignment goes live.
  depends_on = [
    aws_ssoadmin_managed_policy_attachment.this,
    aws_identitystore_group_membership.admin,
  ]
}
