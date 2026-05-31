# Aurora PostgreSQL Serverless v2 vector store (in Security Tooling)
#
# Hosts the pgvector table the Bedrock Knowledge Base reads/writes.
#
# Access: RDS Data API (enable_http_endpoint = true). Bedrock and the
# provisioner Lambda both use the Data API, so the cluster stays private
# with no in-VPC connectivity required.
#
# Encryption: storage + the RDS-managed master-password secret both use
# the security-tooling baseline CMK.

resource "aws_rds_cluster" "kb" {
  provider = aws.security_tooling

  cluster_identifier = "${var.project}-kb"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned" # Serverless v2 uses provisioned + serverlessv2 scaling
  engine_version     = var.aurora_engine_version
  database_name      = var.kb_database_name

  master_username                       = "kbadmin"
  manage_master_user_password           = true
  master_user_secret_kms_key_id         = local.security_tooling_kms_arn

  storage_encrypted = true
  kms_key_id        = local.security_tooling_kms_arn

  # RDS Data API - how Bedrock and the provisioner reach the cluster
  enable_http_endpoint = true

  db_subnet_group_name   = aws_db_subnet_group.kb.name
  vpc_security_group_ids = [aws_security_group.kb_aurora.id]

  serverlessv2_scaling_configuration {
    min_capacity             = var.aurora_min_capacity
    max_capacity             = var.aurora_max_capacity
    seconds_until_auto_pause = var.aurora_seconds_until_auto_pause
  }

  # Portfolio conveniences
  skip_final_snapshot = true
  apply_immediately   = true

  # The master password is RDS-managed; ignore drift on it.
  lifecycle {
    ignore_changes = [master_password]
  }
}

resource "aws_rds_cluster_instance" "kb" {
  provider = aws.security_tooling

  identifier         = "${var.project}-kb-instance"
  cluster_identifier = aws_rds_cluster.kb.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.kb.engine
  engine_version     = aws_rds_cluster.kb.engine_version

  # Not publicly accessible - access is via Data API only.
  publicly_accessible = false
}
