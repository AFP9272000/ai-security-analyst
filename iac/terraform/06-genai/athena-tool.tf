# Athena query tool (Bedrock Agent action group, in Security Tooling)
#
# Lambda that runs structured queries against the findings lake, exposed
# to the agent as the query_security_findings function. No VPC needed
# (Athena is an API call), so no ENI/teardown concerns.
#
# Locals pulled from 04-data state (already declared in providers.tf as
# data.terraform_remote_state.data).

locals {
  athena_workgroup        = data.terraform_remote_state.data.outputs.athena_workgroup_name
  athena_results_arn      = data.terraform_remote_state.data.outputs.athena_results_bucket_arn
  glue_database           = data.terraform_remote_state.data.outputs.glue_database_name
  scored_findings_table   = "scored_findings"
}

data "archive_file" "athena_tool" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/agent-tools/athena_query"
  output_path = "${path.module}/.build/athena-tool.zip"
  excludes    = ["__pycache__", "*.pyc", "README.md"]
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "athena_tool" {
  provider           = aws.security_tooling
  name               = "${var.project}-athena-tool"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  description        = "Execution role for the agent's Athena query tool"
}

data "aws_iam_policy_document" "athena_tool" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-athena-tool",
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-athena-tool:*",
    ]
  }

  statement {
    sid    = "AthenaQuery"
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
    ]
    resources = [
      "arn:aws:athena:${var.region}:${local.security_tooling_id}:workgroup/${local.athena_workgroup}",
    ]
  }

  statement {
    sid    = "GlueCatalogRead"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetTables",
      "glue:GetPartition",
      "glue:GetPartitions",
    ]
    resources = [
      "arn:aws:glue:${var.region}:${local.security_tooling_id}:catalog",
      "arn:aws:glue:${var.region}:${local.security_tooling_id}:database/${local.glue_database}",
      "arn:aws:glue:${var.region}:${local.security_tooling_id}:table/${local.glue_database}/*",
    ]
  }

  # Read the findings data + read/write Athena query results
  statement {
    sid    = "S3DataAndResults"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
      "s3:PutObject",
      "s3:GetBucketLocation",
    ]
    resources = [
      local.enriched_findings_bucket_arn,
      "${local.enriched_findings_bucket_arn}/*",
      local.athena_results_arn,
      "${local.athena_results_arn}/*",
    ]
  }

  statement {
    sid    = "KMSForData"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
      "kms:DescribeKey",
    ]
    resources = [local.security_tooling_kms_arn]
  }
}

resource "aws_iam_role_policy" "athena_tool" {
  provider = aws.security_tooling
  role     = aws_iam_role.athena_tool.id
  name     = "athena-tool"
  policy   = data.aws_iam_policy_document.athena_tool.json
}

resource "aws_cloudwatch_log_group" "athena_tool" {
  provider          = aws.security_tooling
  name              = "/aws/lambda/${var.project}-athena-tool"
  retention_in_days = 30
  kms_key_id        = local.security_tooling_kms_arn
}

resource "aws_lambda_function" "athena_tool" {
  provider = aws.security_tooling

  function_name    = "${var.project}-athena-tool"
  description      = "Agent tool: structured queries against the findings lake"
  role             = aws_iam_role.athena_tool.arn
  runtime          = "python3.12"
  handler          = "lambda_function.handler"
  filename         = data.archive_file.athena_tool.output_path
  source_code_hash = data.archive_file.athena_tool.output_base64sha256
  timeout          = 60
  memory_size      = 256

  environment {
    variables = {
      GLUE_DATABASE    = local.glue_database
      ATHENA_WORKGROUP = local.athena_workgroup
      FINDINGS_TABLE   = local.scored_findings_table
      LOG_LEVEL        = "INFO"
    }
  }

  depends_on = [
    aws_iam_role_policy.athena_tool,
    aws_cloudwatch_log_group.athena_tool,
  ]
}

# Allow the Bedrock agent to invoke this Lambda
resource "aws_lambda_permission" "athena_tool_bedrock" {
  provider = aws.security_tooling

  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.athena_tool.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.analyst.agent_arn
}

# Action group exposing query_security_findings to the agent
resource "aws_bedrockagent_agent_action_group" "athena_tool" {
  provider = aws.security_tooling

  action_group_name = "query-findings"
  agent_id          = aws_bedrockagent_agent.analyst.agent_id
  agent_version     = "DRAFT"
  description       = "Run precise structured queries against the security findings data lake."

  action_group_executor {
    lambda = aws_lambda_function.athena_tool.arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "query_security_findings"
        description = "Query scored security findings with optional filters. Returns matching findings ordered by anomaly score (most anomalous first). Use this for counts, filtered lists, or 'highest risk' style questions where precision matters."

        parameters {
          map_block_key = "severity"
          type          = "string"
          description   = "Optional. Filter by severity: one of low, medium, high, informational."
          required      = false
        }
        parameters {
          map_block_key = "source"
          type          = "string"
          description   = "Optional. Filter by finding source: one of guardduty, securityhub, custom."
          required      = false
        }
        parameters {
          map_block_key = "days_back"
          type          = "integer"
          description   = "Optional. Only findings from the last N days (default 7)."
          required      = false
        }
        parameters {
          map_block_key = "only_anomalies"
          type          = "boolean"
          description   = "Optional. If true, return only findings flagged anomalous by the model."
          required      = false
        }
        parameters {
          map_block_key = "limit"
          type          = "integer"
          description   = "Optional. Max rows to return (default 25, max 100)."
          required      = false
        }
      }
    }
  }
}
