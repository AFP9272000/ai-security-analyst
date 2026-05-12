terraform {
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  backend "s3" {
    # Backend config supplied via -backend-config=../backend.hcl
    # and -backend-config="key=01-foundation/terraform.tfstate"
  }
}
