terraform {
  # NOTE: this layer requires a NEWER AWS provider than layers 00-05.
  # Aurora Serverless v2 scale-to-zero (min_capacity = 0 +
  # seconds_until_auto_pause) landed in provider v5.71.0. Each layer
  # has its own lock file, so this newer constraint is isolated to
  # 06-genai and won't disturb the earlier layers' pins.
  required_version = ">= 1.7.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }

  backend "s3" {
    # Provided via -backend-config=../backend.hcl
  }
}
