# Cross-account DeployRoles
#
# Each member account gets a "DeployRole":
#   - Trusts gha-bootstrap-role in Management (chained assume from GHA OIDC)
#   - Starts with AdministratorAccess in its own account
#   - Will be tightened to layer-scoped policies as each layer ships
#
# Layers 02+ reference the DeployRole ARN in their AWS provider config
# (assume_role.role_arn), not OrganizationAccountAccessRole. OAAR is for
# emergency / break-glass use, not routine CI/CD.
#
# Terraform doesn't support for_each on providers, so each account gets
# its own resource pair. Kept readable rather than abstracted into a module.

locals {
  deploy_role_name = "DeployRole"

  gha_bootstrap_role_arn = "arn:aws:iam::${aws_organizations_organization.this.master_account_id}:role/gha-bootstrap-role"

  deploy_role_assume_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = local.gha_bootstrap_role_arn
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# log-archive

resource "aws_iam_role" "deploy_log_archive" {
  provider = aws.log_archive

  name                 = local.deploy_role_name
  assume_role_policy   = local.deploy_role_assume_policy
  max_session_duration = 3600
  description          = "CI/CD deploy role - trusted by gha-bootstrap-role in Management"
}

resource "aws_iam_role_policy_attachment" "deploy_log_archive_admin" {
  provider   = aws.log_archive
  role       = aws_iam_role.deploy_log_archive.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# security-tooling

resource "aws_iam_role" "deploy_security_tooling" {
  provider = aws.security_tooling

  name                 = local.deploy_role_name
  assume_role_policy   = local.deploy_role_assume_policy
  max_session_duration = 3600
  description          = "CI/CD deploy role - trusted by gha-bootstrap-role in Management"
}

resource "aws_iam_role_policy_attachment" "deploy_security_tooling_admin" {
  provider   = aws.security_tooling
  role       = aws_iam_role.deploy_security_tooling.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# workload

resource "aws_iam_role" "deploy_workload" {
  provider = aws.workload

  name                 = local.deploy_role_name
  assume_role_policy   = local.deploy_role_assume_policy
  max_session_duration = 3600
  description          = "CI/CD deploy role - trusted by gha-bootstrap-role in Management"
}

resource "aws_iam_role_policy_attachment" "deploy_workload_admin" {
  provider   = aws.workload
  role       = aws_iam_role.deploy_workload.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
