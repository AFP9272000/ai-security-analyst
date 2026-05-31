# Provider configuration
#
# Default in Management (CI/CD role). security_tooling alias hosts
# everything: the Aurora vector store, the Knowledge Base, the
# provisioner Lambda, and (in Parts 2-3) the agent + API front door.

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

data "terraform_remote_state" "data" {
  backend = "s3"

  config = {
    bucket         = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
    key            = "04-data/terraform.tfstate"
    region         = var.state_region
    dynamodb_table = "${var.project}-tflocks"
    encrypt        = true
  }
}

locals {
  common_tags = {
    Project     = var.project
    Layer       = "06-genai"
    ManagedBy   = "terraform"
    Environment = "prod"
    CostCenter  = "portfolio"
  }

  security_tooling_id = data.terraform_remote_state.foundation.outputs.account_ids["security-tooling"]
  deploy_role_arns    = data.terraform_remote_state.foundation.outputs.deploy_role_arns
  baseline_key_arns   = data.terraform_remote_state.foundation.outputs.baseline_key_arns

  enriched_findings_bucket     = data.terraform_remote_state.data.outputs.enriched_findings_bucket_name
  enriched_findings_bucket_arn = data.terraform_remote_state.data.outputs.enriched_findings_bucket_arn

  security_tooling_kms_arn = local.baseline_key_arns["security-tooling"]

  # schema.table form Bedrock expects for the RDS vector table
  kb_qualified_table = "${var.kb_schema_name}.${var.kb_table_name}"
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
