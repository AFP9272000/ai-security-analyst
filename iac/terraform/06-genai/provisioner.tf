# Vector-store provisioner (in Security Tooling)
#
# A small Lambda that runs the pgvector DDL via the RDS Data API, invoked
# once at apply time. The Knowledge Base can't be created until the
# target table exists, so the KB resource depends_on this invocation.
#
# No VPC config: the Lambda uses the Data API (HTTPS), not a direct
# Postgres connection. This keeps it ENI-free and teardown-safe.

data "archive_file" "kb_provisioner" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/kb-provisioner"
  output_path = "${path.module}/.build/kb-provisioner.zip"
  excludes    = ["__pycache__", "*.pyc", "README.md"]
}

data "aws_iam_policy_document" "kb_provisioner_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "kb_provisioner" {
  provider = aws.security_tooling

  name               = "${var.project}-kb-provisioner"
  assume_role_policy = data.aws_iam_policy_document.kb_provisioner_assume.json
  description        = "Runs pgvector DDL via the RDS Data API"
}

data "aws_iam_policy_document" "kb_provisioner" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-kb-provisioner",
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-kb-provisioner:*",
    ]
  }

  statement {
    sid    = "RDSDataAPI"
    effect = "Allow"
    actions = [
      "rds-data:ExecuteStatement",
      "rds-data:BatchExecuteStatement",
    ]
    resources = [aws_rds_cluster.kb.arn]
  }

  statement {
    sid    = "ReadDBSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_rds_cluster.kb.master_user_secret[0].secret_arn]
  }

  statement {
    sid    = "KMSDecrypt"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [local.security_tooling_kms_arn]
  }
}

resource "aws_iam_role_policy" "kb_provisioner" {
  provider = aws.security_tooling

  role   = aws_iam_role.kb_provisioner.id
  name   = "kb-provisioner"
  policy = data.aws_iam_policy_document.kb_provisioner.json
}

resource "aws_cloudwatch_log_group" "kb_provisioner" {
  provider = aws.security_tooling

  name              = "/aws/lambda/${var.project}-kb-provisioner"
  retention_in_days = 30
  kms_key_id        = local.security_tooling_kms_arn
}

resource "aws_lambda_function" "kb_provisioner" {
  provider = aws.security_tooling

  function_name    = "${var.project}-kb-provisioner"
  description      = "Creates pgvector schema/table for the Knowledge Base via RDS Data API"
  role             = aws_iam_role.kb_provisioner.arn
  runtime          = "python3.12"
  handler          = "lambda_function.handler"
  filename         = data.archive_file.kb_provisioner.output_path
  source_code_hash = data.archive_file.kb_provisioner.output_base64sha256
  timeout          = 300 # generous: a paused cluster can take ~30s to resume
  memory_size      = 256

  environment {
    variables = {
      CLUSTER_ARN   = aws_rds_cluster.kb.arn
      SECRET_ARN    = aws_rds_cluster.kb.master_user_secret[0].secret_arn
      DATABASE_NAME = var.kb_database_name
      SCHEMA_NAME   = var.kb_schema_name
      TABLE_NAME    = var.kb_table_name
      VECTOR_DIMS   = tostring(var.vector_dimensions)
    }
  }

  depends_on = [
    aws_iam_role_policy.kb_provisioner,
    aws_cloudwatch_log_group.kb_provisioner,
    aws_rds_cluster_instance.kb, # ensure the cluster is actually up
  ]
}

# Invoke the provisioner at apply time to create the schema. The DDL is
# idempotent (IF NOT EXISTS), and the input carries a version string so
# i can force a re-run by bumping it if the schema ever changes.
resource "aws_lambda_invocation" "kb_provisioner" {
  provider = aws.security_tooling

  function_name = aws_lambda_function.kb_provisioner.function_name

  input = jsonencode({
    ddl_version = "v1"
  })

  depends_on = [aws_lambda_function.kb_provisioner]
}
