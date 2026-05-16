# Provider configuration
#
# Default provider runs in Management (where the CI/CD role lives).
# Aliased providers chain-assume the per-account DeployRole created in
# 01-foundation/iam.tf.

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
    Layer       = "02-network"
    ManagedBy   = "terraform"
    Environment = "prod"
    CostCenter  = "portfolio"
  }

  deploy_role_arns  = data.terraform_remote_state.foundation.outputs.deploy_role_arns
  baseline_key_arns = data.terraform_remote_state.foundation.outputs.baseline_key_arns
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "workload"
  region = var.region

  assume_role {
    role_arn = local.deploy_role_arns["workload"]
  }

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "security_tooling"
  region = var.region

  assume_role {
    role_arn = local.deploy_role_arns["security-tooling"]
  }

  default_tags {
    tags = local.common_tags
  }
}
