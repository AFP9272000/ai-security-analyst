# Provider configuration
#
# Default in Management (where CloudTrail org trail lives).
# log_archive alias for the immutable log bucket.
# security_tooling alias for GuardDuty/Security Hub/EventBridge config in
# the delegated admin account.
# workload alias used by data sources confirming member account IDs.

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
    Layer       = "03-telemetry"
    ManagedBy   = "terraform"
    Environment = "prod"
    CostCenter  = "portfolio"
  }

  org_id                 = data.terraform_remote_state.foundation.outputs.organization_id
  mgmt_account_id        = data.terraform_remote_state.foundation.outputs.management_account_id
  log_archive_account_id = data.terraform_remote_state.foundation.outputs.account_ids["log-archive"]
  security_tooling_id    = data.terraform_remote_state.foundation.outputs.account_ids["security-tooling"]
  workload_account_id    = data.terraform_remote_state.foundation.outputs.account_ids["workload"]
  deploy_role_arns       = data.terraform_remote_state.foundation.outputs.deploy_role_arns
  baseline_key_arns      = data.terraform_remote_state.foundation.outputs.baseline_key_arns
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "log_archive"
  region = var.region

  assume_role {
    role_arn = local.deploy_role_arns["log-archive"]
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
