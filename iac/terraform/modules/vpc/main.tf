# Wrapper around terraform-aws-modules/vpc/aws.
# Enforces project conventions: no NAT, no default SG management, encrypted
# flow logs with project-managed retention, naming and tag discipline.

terraform {
  required_version = ">= 1.7.0"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 5.40"
      configuration_aliases = [aws]
    }
  }
}

locals {
  has_public = length(var.public_subnet_cidrs) > 0

  merged_tags = merge(
    {
      Name      = var.name
      ManagedBy = "terraform"
    },
    var.tags,
  )
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13.0"

  name = var.name
  cidr = var.cidr
  azs  = var.azs

  public_subnets   = var.public_subnet_cidrs
  private_subnets  = var.private_subnet_cidrs
  database_subnets = var.database_subnet_cidrs

  enable_dns_hostnames = true
  enable_dns_support   = true

  # No NAT, ever. Project pattern uses interface endpoints.
  enable_nat_gateway = false
  single_nat_gateway = false
  one_nat_gateway_per_az = false

  # IGW only if there are public subnets.
  create_igw = local.has_public

  # Don't manage the default SG - leave it as AWS-default-deny via best-
  # practice approach; explicit SGs are created where needed.
  manage_default_security_group = false

  # Database tier gets a dedicated, isolated route table.
  create_database_subnet_route_table = length(var.database_subnet_cidrs) > 0
  create_database_internet_gateway_route = false

  tags = local.merged_tags

  public_subnet_tags = {
    Tier = "public"
  }
  private_subnet_tags = {
    Tier = "private-app"
  }
  database_subnet_tags = {
    Tier = "private-data"
  }
}

# Flow logs, CloudWatch Logs with KMS encryption and bounded retention.

resource "aws_cloudwatch_log_group" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name              = "/aws/vpc/${var.name}/flow-logs"
  retention_in_days = var.flow_logs_retention_days
  kms_key_id        = var.flow_logs_kms_key_arn

  tags = local.merged_tags
}

resource "aws_iam_role" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  name = "${var.name}-flow-logs"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = local.merged_tags
}

resource "aws_iam_role_policy" "flow_logs" {
  count = var.enable_flow_logs ? 1 : 0

  role = aws_iam_role.flow_logs[0].id
  name = "write-flow-logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = "${aws_cloudwatch_log_group.flow_logs[0].arn}:*"
    }]
  })
}

resource "aws_flow_log" "this" {
  count = var.enable_flow_logs ? 1 : 0

  vpc_id          = module.vpc.vpc_id
  traffic_type    = "ALL"
  log_destination = aws_cloudwatch_log_group.flow_logs[0].arn
  iam_role_arn    = aws_iam_role.flow_logs[0].arn
  log_format      = "$${version} $${account-id} $${interface-id} $${srcaddr} $${dstaddr} $${srcport} $${dstport} $${protocol} $${packets} $${bytes} $${start} $${end} $${action} $${log-status} $${vpc-id} $${subnet-id} $${instance-id} $${tcp-flags} $${type} $${pkt-srcaddr} $${pkt-dstaddr} $${region} $${az-id} $${sublocation-type} $${sublocation-id}"

  tags = local.merged_tags
}
