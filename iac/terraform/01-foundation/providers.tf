# Provider configuration
#
# Default provider runs in the Management account (the credentials the
# CI/CD assumes via gha-bootstrap-role).
#
# Aliased providers chain-assume the auto-created OrganizationAccountAccessRole
# in each member account to provision resources there.

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
    role_arn = "arn:aws:iam::${aws_organizations_account.members["log-archive"].id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "security_tooling"
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.members["security-tooling"].id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = local.common_tags
  }
}

provider "aws" {
  alias  = "workload"
  region = var.region

  assume_role {
    role_arn = "arn:aws:iam::${aws_organizations_account.members["workload"].id}:role/OrganizationAccountAccessRole"
  }

  default_tags {
    tags = local.common_tags
  }
}
