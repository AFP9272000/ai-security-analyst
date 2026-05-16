# Security Tooling account VPC
#
# Private subnets only. Houses SageMaker training jobs and inference
# endpoints (VPC mode), Lambdas, and any other service that needs to be
# air-gapped from the internet. All AWS API access via interface endpoints.

module "security_tooling_vpc" {
  source = "../modules/vpc"

  providers = {
    aws = aws.security_tooling
  }

  name = "${var.project}-security-tooling"
  cidr = var.security_tooling_vpc_cidr
  azs  = var.azs

  # No public subnets - this VPC has no internet egress.
  public_subnet_cidrs  = []
  private_subnet_cidrs = ["10.20.0.0/24", "10.20.1.0/24"]
  # No database tier here - the platform stores data in S3/DynamoDB
  # accessed via endpoints, not in VPC-resident databases.
  database_subnet_cidrs = []

  flow_logs_kms_key_arn = local.baseline_key_arns["security-tooling"]

  tags = { Layer = "02-network" }
}

resource "aws_security_group" "security_tooling_endpoints" {
  provider = aws.security_tooling

  name        = "${var.project}-security-tooling-endpoints"
  description = "Allow HTTPS from security tooling VPC CIDR to interface endpoints"
  vpc_id      = module.security_tooling_vpc.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [module.security_tooling_vpc.vpc_cidr_block]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
