# Provider configuration
#
# Default provider in Management (CI/CD role). The security_tooling alias
# hosts the alerting resources (SNS, EventBridge rules, triage Lambda),
# alongside the agent it triages with.
#
# Reads remote state from:
#   - 01-foundation : account ids, deploy roles, baseline KMS keys
#   - 06-genai      : the agent id (the triage Lambda invokes it)


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

data "terraform_remote_state" "genai" {
  backend = "s3"

  config = {
    bucket         = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
    key            = "06-genai/terraform.tfstate"
    region         = var.state_region
    dynamodb_table = "${var.project}-tflocks"
    encrypt        = true
  }
}

locals {
  common_tags = {
    Project     = var.project
    Layer       = "07-integration"
    ManagedBy   = "terraform"
    Environment = "prod"
    CostCenter  = "portfolio"
  }

  security_tooling_id = data.terraform_remote_state.foundation.outputs.account_ids["security-tooling"]
  deploy_role_arns    = data.terraform_remote_state.foundation.outputs.deploy_role_arns
  baseline_key_arns   = data.terraform_remote_state.foundation.outputs.baseline_key_arns

  security_tooling_kms_arn = local.baseline_key_arns["security-tooling"]

  # The agent the triage Lambda invokes (from 06-genai state)
  agent_id = data.terraform_remote_state.genai.outputs.agent_id
}

provider "aws" {
  region = var.region

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
