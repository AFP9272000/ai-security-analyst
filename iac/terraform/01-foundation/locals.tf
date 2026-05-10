locals {
  common_tags = {
    Project     = var.project
    Layer       = "01-foundation"
    ManagedBy   = "terraform"
    Environment = "prod"
    CostCenter  = "portfolio"
  }

  email_local  = split("@", var.root_email)[0]
  email_domain = split("@", var.root_email)[1]

  accounts = {
    log-archive = {
      name = "${var.project}-log-archive"
      tag  = "log-archive"
      ou   = "security"
    }
    security-tooling = {
      name = "${var.project}-security-tooling"
      tag  = "security-tooling"
      ou   = "security"
    }
    workload = {
      name = "${var.project}-workload"
      tag  = "workload"
      ou   = "workload"
    }
  }

  ou_id_map = {
    security = aws_organizations_organizational_unit.security.id
    workload = aws_organizations_organizational_unit.workload.id
  }
}
