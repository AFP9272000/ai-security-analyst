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
  description = "IAM Identity Center instance ARN"
  value       = local.sso_instance_arn
}

output "sso_identity_store_id" {
  description = "Identity Store ID backing this Identity Center instance"
  value       = local.sso_identity_store
}

output "admin_user_id" {
  description = "Identity Store user ID for the admin user"
  value       = aws_identitystore_user.admin.user_id
}

output "admins_group_id" {
  description = "Identity Store group ID for the Administrators group"
  value       = aws_identitystore_group.admins.group_id
}

output "permission_set_arns" {
  description = "ARNs of created permission sets, keyed by short name"
  value = {
    for k, v in aws_ssoadmin_permission_set.this : k => v.arn
  }
}

output "access_portal_login_email" {
  description = "Email that will receive the Identity Center invitation"
  value       = var.root_email
  sensitive   = true
}
