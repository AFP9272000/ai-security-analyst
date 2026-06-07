# Provider configuration
#
# Default provider = Management (CI/CD role / payer account). Used for
# org-level cost resources (Budgets, Cost Anomaly Detection).
#
# security_tooling alias = where the platform's resources run and emit
# CloudWatch metrics. The dashboard and alarms live here.
#
# Reads remote state from:
#   - 01-foundation : account ids, deploy roles
#   - 06-genai      : chat API endpoint + conversation table (for metrics)
#   - 07-integration: alert SNS topic (alarm actions)

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

data "terraform_remote_state" "integration" {
  backend = "s3"
  config = {
    bucket         = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
    key            = "07-integration/terraform.tfstate"
    region         = var.state_region
    dynamodb_table = "${var.project}-tflocks"
    encrypt        = true
  }
}

locals {
  common_tags = {
    Project     = var.project
    Layer       = "08-observability"
    ManagedBy   = "terraform"
    Environment = "prod"
    CostCenter  = "portfolio"
  }

  deploy_role_arns = data.terraform_remote_state.foundation.outputs.deploy_role_arns

  alert_topic_arn       = data.terraform_remote_state.integration.outputs.alert_topic_arn
  conversation_table    = data.terraform_remote_state.genai.outputs.conversation_table_name
  chat_api_endpoint     = data.terraform_remote_state.genai.outputs.chat_api_endpoint
  # Parse the HTTP API id out of the endpoint URL
  # (https://<apiId>.execute-api.<region>.amazonaws.com)
  chat_api_id           = split(".", replace(local.chat_api_endpoint, "https://", ""))[0]

  # Deterministic resource names (project prefix)
  lambda_names = [
    "enricher",
    "inference",
    "orchestrator",
    "triage",
    "kb-provisioner",
    "athena-tool",
    "config-tool",
  ]
  critical_lambdas = ["orchestrator", "triage", "enricher", "inference"]

  guardduty_rule   = "${var.project}-guardduty-high-sev"
  securityhub_rule = "${var.project}-securityhub-high-sev"
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
