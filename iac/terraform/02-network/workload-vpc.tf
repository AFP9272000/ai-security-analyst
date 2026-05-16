# Workload account VPC
#
# 3-tier: public (IGW), private app, private database (isolated).
# Realistic prod-shaped surface for the simulated workload that generates
# CloudTrail events.

module "workload_vpc" {
  source = "../modules/vpc"

  providers = {
    aws = aws.workload
  }

  name = "${var.project}-workload"
  cidr = var.workload_vpc_cidr
  azs  = var.azs

  public_subnet_cidrs   = ["10.10.0.0/24", "10.10.1.0/24"]
  private_subnet_cidrs  = ["10.10.10.0/24", "10.10.11.0/24"]
  database_subnet_cidrs = ["10.10.20.0/24", "10.10.21.0/24"]

  flow_logs_kms_key_arn = local.baseline_key_arns["workload"]

  tags = { Layer = "02-network" }
}

# Security group for interface endpoints in the workload VPC.
# Permits 443 from the VPC CIDR; nothing else.
resource "aws_security_group" "workload_endpoints" {
  provider = aws.workload

  name        = "${var.project}-workload-endpoints"
  description = "Allow HTTPS from workload VPC CIDR to interface endpoints"
  vpc_id      = module.workload_vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.workload_vpc.vpc_cidr_block]
  }

  egress {
    description = "All outbound (AWS-API only via endpoints)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
