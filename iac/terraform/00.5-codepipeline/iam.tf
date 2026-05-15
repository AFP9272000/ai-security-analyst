# CodePipeline service role

resource "aws_iam_role" "codepipeline" {
  name = "${var.project}-codepipeline-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codepipeline.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "codepipeline" {
  role = aws_iam_role.codepipeline.id
  name = "pipeline-permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ArtifactBucket"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:PutObject",
          "s3:GetBucketVersioning",
          "s3:ListBucket",
        ]
        Resource = [
          aws_s3_bucket.artifacts.arn,
          "${aws_s3_bucket.artifacts.arn}/*",
        ]
      },
      {
        Sid      = "ArtifactKMS"
        Effect   = "Allow"
        Action   = ["kms:Decrypt", "kms:GenerateDataKey", "kms:DescribeKey"]
        Resource = aws_kms_key.artifacts.arn
      },
      {
        Sid      = "CodeConnections"
        Effect   = "Allow"
        Action   = ["codestar-connections:UseConnection", "codeconnections:UseConnection"]
        Resource = var.codeconnections_arn
      },
      {
        Sid      = "InvokeCodeBuild"
        Effect   = "Allow"
        Action   = ["codebuild:BatchGetBuilds", "codebuild:StartBuild", "codebuild:StopBuild"]
        Resource = "*"
      },
      {
        Sid      = "PassRoleToCodeBuild"
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = aws_iam_role.codebuild.arn
      }
    ]
  })
}

# CodeBuild service role, mirrors gha-bootstrap-role's purpose for CodePipeline.
# Same trust pattern: this role chain-assumes into member-account DeployRoles.

resource "aws_iam_role" "codebuild" {
  name = "${var.project}-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "codebuild.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

# CodeBuild needs admin in Management to deploy 01-foundation and to update
# itself. Tightened later. Parity with gha-bootstrap-role.
resource "aws_iam_role_policy_attachment" "codebuild_admin" {
  role       = aws_iam_role.codebuild.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# DeployRoles in member accounts must also trust this CodeBuild role.
# add an additional-trust update via a separate resource per account so
# the foundation layer's existing DeployRole trust survives.
locals {
  member_account_ids = data.terraform_remote_state.foundation.outputs.account_ids
  member_account_id_list = [
    local.member_account_ids["log-archive"],
    local.member_account_ids["security-tooling"],
    local.member_account_ids["workload"],
  ]
}

# CodeBuild needs to assume any DeployRole. The trust on the DeployRole side
# (in foundation layer) currently only lists gha-bootstrap-role. grant
# CodeBuild's permission side here and update the foundation trust policies
resource "aws_iam_role_policy" "codebuild_assume_deploy_roles" {
  role = aws_iam_role.codebuild.id
  name = "assume-deploy-roles"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = "sts:AssumeRole"
      Resource = [
        for id in local.member_account_id_list :
        "arn:aws:iam::${id}:role/DeployRole"
      ]
    }]
  })
}
