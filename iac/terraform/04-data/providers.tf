# Provider configuration
#
# Default in Management (where CI/CD role lives).
# security_tooling alias: Glue catalog + Athena workgroup + enriched bucket
#   all live here.
# log_archive alias: read-only access for verification queries (the bucket
#   policy on log-archive's bucket grants security-tooling access; we
#   don't actually need to deploy anything here, but the provider is
#   declared for consistency).

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

data "terraform_remote_state" "telemetry" {
  backend = "s3"

  config = {
    bucket         = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
    key            = "03-telemetry/terraform.tfstate"
    region         = var.state_region
    dynamodb_table = "${var.project}-tflocks"
    encrypt        = true
  }
}

locals {
  common_tags = {
    Project     = var.project
    Layer       = "04-data"
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

  log_archive_bucket_name = try(data.terraform_remote_state.telemetry.outputs.log_archive_bucket_name, "placeholder-bucket")
  log_archive_bucket_arn  = try(data.terraform_remote_state.telemetry.outputs.log_archive_bucket_arn, "arn:aws:s3:::placeholder-bucket")
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
