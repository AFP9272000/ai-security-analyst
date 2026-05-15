data "aws_caller_identity" "current" {}

data "terraform_remote_state" "foundation" {
  backend = "s3"

  config = {
    bucket         = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
    key            = "01-foundation/terraform.tfstate"
    region         = var.state_region
    dynamodb_table = "${var.project}-tflocks"
    encrypt        = true
  }
}

locals {
  common_tags = {
    Project     = var.project
    Layer       = "00.5-codepipeline"
    ManagedBy   = "terraform"
    Environment = "prod"
    CostCenter  = "portfolio"
  }

  mgmt_account_id        = data.aws_caller_identity.current.account_id
  gha_bootstrap_role_arn = "arn:aws:iam::${local.mgmt_account_id}:role/gha-bootstrap-role"

  # All four pipelines we provision.
  pipelines = {
    tf-validate = {
      buildspec         = "codepipeline/buildspecs/tf-validate.yml"
      requires_approval = false
      apply_buildspec   = null
    }
    tf-deploy = {
      buildspec         = "codepipeline/buildspecs/tf-plan.yml"
      requires_approval = true
      apply_buildspec   = "codepipeline/buildspecs/tf-apply.yml"
    }
    cfn-validate = {
      buildspec         = "codepipeline/buildspecs/cfn-validate.yml"
      requires_approval = false
      apply_buildspec   = null
    }
    cfn-deploy = {
      buildspec         = "codepipeline/buildspecs/cfn-changeset.yml"
      requires_approval = true
      apply_buildspec   = "codepipeline/buildspecs/cfn-deploy.yml"
    }
  }
}
