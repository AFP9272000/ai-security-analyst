# Cross-account DeployRoles
#
# Each member account gets a "DeployRole":
#   - Trusts gha-bootstrap-role in Management (GitHub Actions CI/CD path)
#   - Trusts ai-sec-analyst-codebuild-role in Management (CodePipeline CI/CD
#     path added)
#   - Starts with AdministratorAccess in its own account
#   - Will be tightened to layer-scoped policies as each layer ships
#
# The CodeBuild role lives in the 00.5-codepipeline layer. read its ARN
# from that layer's remote state. This creates a dependency: 01-foundation
# must be deployed before 00.5-codepipeline, then 01-foundation re-applied
# to pick up the CodeBuild trust. Documented in docs/adr/0004.

data "aws_caller_identity" "current" {}

# Read the CodeBuild role ARN from the codepipeline layer's state.
# Use the count pattern to make this optional: if the codepipeline layer
# hasn't been deployed yet, this layer still applies without the trust.

data "terraform_remote_state" "codepipeline" {
  count   = var.codepipeline_layer_deployed ? 1 : 0
  backend = "s3"

  config = {
    bucket         = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
    key            = "00.5-codepipeline/terraform.tfstate"
    region         = var.state_region
    dynamodb_table = "${var.project}-tflocks"
    encrypt        = true
  }
}

locals {
  deploy_role_name = "DeployRole"

  gha_bootstrap_role_arn = "arn:aws:iam::${aws_organizations_organization.this.master_account_id}:role/gha-bootstrap-role"

  # Conditionally include the CodeBuild role principal.
  codebuild_role_arn = (
    var.codepipeline_layer_deployed
    ? data.terraform_remote_state.codepipeline[0].outputs.codebuild_role_arn
    : null
  )

  deploy_role_trusted_principals = compact([
    local.gha_bootstrap_role_arn,
    local.codebuild_role_arn,
  ])

  deploy_role_assume_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        AWS = local.deploy_role_trusted_principals
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
  description          = "CI/CD deploy role - trusted by gha-bootstrap-role and codebuild-role in Management"
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
  description          = "CI/CD deploy role - trusted by gha-bootstrap-role and codebuild-role in Management"
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
  description          = "CI/CD deploy role - trusted by gha-bootstrap-role and codebuild-role in Management"
}

resource "aws_iam_role_policy_attachment" "deploy_workload_admin" {
  provider   = aws.workload
  role       = aws_iam_role.deploy_workload.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
