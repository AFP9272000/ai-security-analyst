# Config state tool (Bedrock Agent action group, in Security Tooling)
#
# Lambda exposing get_resource_configuration to the agent. Uses AWS
# Config advanced query (select_resource_config) against the local
# account's recordings. No VPC needed.

data "archive_file" "config_tool" {
  type        = "zip"
  source_dir  = "${path.module}/../../../lambdas/agent-tools/config_state"
  output_path = "${path.module}/.build/config-tool.zip"
  excludes    = ["__pycache__", "*.pyc", "README.md"]
}

resource "aws_iam_role" "config_tool" {
  provider           = aws.security_tooling
  name               = "${var.project}-config-tool"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  description        = "Execution role for the agent's Config state tool"
}

data "aws_iam_policy_document" "config_tool" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = [
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-config-tool",
      "arn:aws:logs:${var.region}:${local.security_tooling_id}:log-group:/aws/lambda/${var.project}-config-tool:*",
    ]
  }

  # Config advanced query. SelectResourceConfig is not resource-scopable,
  # so it must be "*"; it is read-only.
  statement {
    sid    = "ConfigQuery"
    effect = "Allow"
    actions = [
      "config:SelectResourceConfig",
      "config:BatchGetResourceConfig",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "config_tool" {
  provider = aws.security_tooling
  role     = aws_iam_role.config_tool.id
  name     = "config-tool"
  policy   = data.aws_iam_policy_document.config_tool.json
}

resource "aws_cloudwatch_log_group" "config_tool" {
  provider          = aws.security_tooling
  name              = "/aws/lambda/${var.project}-config-tool"
  retention_in_days = 30
  kms_key_id        = local.security_tooling_kms_arn
}

resource "aws_lambda_function" "config_tool" {
  provider = aws.security_tooling

  function_name    = "${var.project}-config-tool"
  description      = "Agent tool: look up current AWS resource configuration via Config"
  role             = aws_iam_role.config_tool.arn
  runtime          = "python3.12"
  handler          = "lambda_function.handler"
  filename         = data.archive_file.config_tool.output_path
  source_code_hash = data.archive_file.config_tool.output_base64sha256
  timeout          = 30
  memory_size      = 256

  environment {
    variables = {
      LOG_LEVEL = "INFO"
    }
  }

  depends_on = [
    aws_iam_role_policy.config_tool,
    aws_cloudwatch_log_group.config_tool,
  ]
}

resource "aws_lambda_permission" "config_tool_bedrock" {
  provider = aws.security_tooling

  statement_id  = "AllowBedrockAgentInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.config_tool.function_name
  principal     = "bedrock.amazonaws.com"
  source_arn    = aws_bedrockagent_agent.analyst.agent_arn
}

resource "aws_bedrockagent_agent_action_group" "config_tool" {
  provider = aws.security_tooling

  action_group_name = "resource-config"
  agent_id          = aws_bedrockagent_agent.analyst.agent_id
  agent_version     = "DRAFT"
  description       = "Look up the current configuration of an AWS resource."

  action_group_executor {
    lambda = aws_lambda_function.config_tool.arn
  }

  function_schema {
    member_functions {
      functions {
        name        = "get_resource_configuration"
        description = "Get the current AWS Config-recorded configuration of a resource by its resource ID or ARN. Use this to ground an answer in the resource's live state (e.g. a security group's rules, an S3 bucket's settings) rather than only the finding snapshot. Note: v1 sees only this account's resources."

        parameters {
          map_block_key = "resource_id"
          type          = "string"
          description   = "The resource ID or ARN to look up (e.g. an instance ID, bucket name, or full ARN)."
          required      = true
        }
      }
    }
  }
}
