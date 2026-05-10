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
