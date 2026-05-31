# Persistent network for the Aurora vector store (in Security Tooling)
#
# Why a dedicated vpc: Aurora must live in a VPC with a DB subnet group
# spanning >= 2 AZs. The 02-network VPC is EPHEMERAL (torn down between
# sessions). If Aurora lived there, every network teardown would break
# the Knowledge Base. So 06-genai provisions its own minimal, persistent
# VPC that is NOT part of the build/destroy lifecycle.
#
# This VPC is deliberately bare: two private subnets, a DB subnet group,
# and a security group. No IGW, no NAT, no endpoints. Nothing needs to
# reach Aurora over the network directly, both Bedrock and the
# provisioner Lambda talk to it via the RDS Data API (an AWS-managed
# HTTPS control path), so no in-VPC connectivity or routing is required.
# See docs/adr/0013-vector-store-aurora-pgvector.md.

data "aws_availability_zones" "available" {
  provider = aws.security_tooling
  state    = "available"
}

resource "aws_vpc" "kb" {
  provider = aws.security_tooling

  cidr_block           = "10.20.0.0/24"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.project}-kb-vpc"
  }
}

resource "aws_subnet" "kb" {
  provider = aws.security_tooling
  count    = 2

  vpc_id            = aws_vpc.kb.id
  cidr_block        = cidrsubnet(aws_vpc.kb.cidr_block, 2, count.index) # /26 each
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name = "${var.project}-kb-subnet-${count.index}"
  }
}

resource "aws_db_subnet_group" "kb" {
  provider = aws.security_tooling

  name       = "${var.project}-kb"
  subnet_ids = aws_subnet.kb[*].id
}

# Security group with NO ingress. Access to Aurora is via the Data API,
# which does not traverse the security group. Egress open for the
# cluster's own outbound needs (telemetry, etc.).
resource "aws_security_group" "kb_aurora" {
  provider = aws.security_tooling

  name        = "${var.project}-kb-aurora"
  description = "Aurora vector store - no direct ingress; access via RDS Data API"
  vpc_id      = aws_vpc.kb.id

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project}-kb-aurora"
  }
}
