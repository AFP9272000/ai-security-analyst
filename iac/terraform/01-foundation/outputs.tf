output "organization_id" {
  description = "AWS Organization ID"
  value       = aws_organizations_organization.this.id
}

output "organization_arn" {
  description = "AWS Organization ARN"
  value       = aws_organizations_organization.this.arn
}

output "management_account_id" {
  description = "Management account ID"
  value       = aws_organizations_organization.this.master_account_id
}

output "security_ou_id" {
  value = aws_organizations_organizational_unit.security.id
}

output "workload_ou_id" {
  value = aws_organizations_organizational_unit.workload.id
}

output "account_ids" {
  description = "Map of account name to account ID"
  value = {
    for k, v in aws_organizations_account.members : k => v.id
  }
}

output "account_arns" {
  description = "Map of account name to account ARN"
  value = {
    for k, v in aws_organizations_account.members : k => v.arn
  }
}

# Identity Center 

output "sso_instance_arn" {
  value = local.sso_instance_arn
}

output "sso_identity_store_id" {
  value = local.sso_identity_store
}

output "admin_user_id" {
  value = aws_identitystore_user.admin.user_id
}

output "admins_group_id" {
  value = aws_identitystore_group.admins.group_id
}

output "permission_set_arns" {
  value = {
    for k, v in aws_ssoadmin_permission_set.this : k => v.arn
  }
}

output "access_portal_login_email" {
  value     = var.root_email
  sensitive = true
}

# Cross-account DeployRoles 

output "deploy_role_arns" {
  value = {
    log-archive      = aws_iam_role.deploy_log_archive.arn
    security-tooling = aws_iam_role.deploy_security_tooling.arn
    workload         = aws_iam_role.deploy_workload.arn
  }
}

# Baseline KMS keys 

output "baseline_key_arns" {
  value = {
    log-archive      = aws_kms_key.baseline_log_archive.arn
    security-tooling = aws_kms_key.baseline_security_tooling.arn
    workload         = aws_kms_key.baseline_workload.arn
  }
}

output "baseline_key_alias" {
  value = local.baseline_key_alias
}

# Delegated administrators 

output "delegated_admin_account_id" {
  description = "Account ID that holds delegated admin for security services (Security Tooling)"
  value       = local.security_tooling_account_id
}

output "delegated_admin_services" {
  description = "Services for which Security Tooling is the delegated admin"
  value = [
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "config.amazonaws.com",
    "config-multiaccountsetup.amazonaws.com",
  ]
}
