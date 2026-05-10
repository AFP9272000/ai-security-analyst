resource "aws_organizations_account" "members" {
  for_each = local.accounts

  name      = each.value.name
  email     = "${local.email_local}+ai-sec-${each.value.tag}@${local.email_domain}"
  parent_id = local.ou_id_map[each.value.ou]

  # OrganizationAccountAccessRole is created automatically and trusts the
  # management account. CI/CD chains assume from gha-bootstrap-role into it.
  role_name = "OrganizationAccountAccessRole"

  # Block IAM users in the account from seeing billing; only management can.
  iam_user_access_to_billing = "DENY"

  # AWS Organizations imposes a 30-day cooldown on closing accounts.
  # If destroying this layer, the accounts remain in SUSPENDED state.
  lifecycle {
    ignore_changes = [role_name]
  }
}
