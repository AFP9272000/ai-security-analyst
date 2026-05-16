# VPC endpoints
#
# Interface endpoints (PrivateLink): per-AZ ENI, ~$7.30/AZ/month each
# Gateway endpoints (S3, DynamoDB): free, attached to route tables
#
# Workload VPC gets a smaller set of endpoints because its private subnets
# need less AWS API access. Security Tooling VPC gets the larger set
# because that's where SageMaker, Lambda, Bedrock, etc. all run.

locals {
  # Endpoints needed in the Security Tooling VPC (full ML/AI stack).
  security_tooling_interface_endpoints = [
    "kms",
    "secretsmanager",
    "sagemaker.api",
    "sagemaker.runtime",
    "ecr.api",
    "ecr.dkr",
    "bedrock",
    "bedrock-runtime",
    "bedrock-agent",
    "bedrock-agent-runtime",
    "logs",
    "monitoring",
    "sts",
  ]

  # Endpoints in Workload VPC - minimal, just enough for SSM-managed
  # instances and CloudWatch logging from app tier.
  workload_interface_endpoints = [
    "ssm",
    "ssmmessages",
    "ec2messages",
    "logs",
    "monitoring",
    "kms",
  ]
}

# Security Tooling VPC endpoints

# Gateway endpoint for S3 (free)
resource "aws_vpc_endpoint" "security_tooling_s3" {
  provider = aws.security_tooling

  vpc_id          = module.security_tooling_vpc.vpc_id
  service_name    = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids = module.security_tooling_vpc.private_route_table_ids

  tags = { Name = "${var.project}-security-tooling-s3" }
}

# Gateway endpoint for DynamoDB (free)
resource "aws_vpc_endpoint" "security_tooling_dynamodb" {
  provider = aws.security_tooling

  vpc_id            = module.security_tooling_vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = module.security_tooling_vpc.private_route_table_ids

  tags = { Name = "${var.project}-security-tooling-dynamodb" }
}

# Interface endpoints (paid; one ENI per AZ per endpoint)
resource "aws_vpc_endpoint" "security_tooling_interface" {
  provider = aws.security_tooling

  for_each = toset(local.security_tooling_interface_endpoints)

  vpc_id              = module.security_tooling_vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.security_tooling_vpc.private_subnet_ids
  security_group_ids  = [aws_security_group.security_tooling_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.project}-security-tooling-${each.value}" }
}

# Workload VPC endpoints

resource "aws_vpc_endpoint" "workload_s3" {
  provider = aws.workload

  vpc_id            = module.workload_vpc.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = concat(
    module.workload_vpc.private_route_table_ids,
    module.workload_vpc.database_route_table_ids,
  )

  tags = { Name = "${var.project}-workload-s3" }
}

resource "aws_vpc_endpoint" "workload_interface" {
  provider = aws.workload

  for_each = toset(local.workload_interface_endpoints)

  vpc_id              = module.workload_vpc.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = module.workload_vpc.private_subnet_ids
  security_group_ids  = [aws_security_group.workload_endpoints.id]
  private_dns_enabled = true

  tags = { Name = "${var.project}-workload-${each.value}" }
}
