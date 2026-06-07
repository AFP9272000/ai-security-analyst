# CloudWatch dashboard SOC platform single pane of glass (Security Tooling)
#
# Widgets are built from deterministic resource names (project prefix)
# plus the chat API id and conversation table parsed from 06-genai state.
# The Aurora ACU widget is included only if kb_cluster_identifier is set.

locals {
  # Metric arrays generated from the Lambda name list
  invocation_metrics = [for n in local.lambda_names : ["AWS/Lambda", "Invocations", "FunctionName", "${var.project}-${n}"]]
  error_metrics      = [for n in local.lambda_names : ["AWS/Lambda", "Errors", "FunctionName", "${var.project}-${n}"]]
  duration_metrics   = [for n in local.critical_lambdas : ["AWS/Lambda", "Duration", "FunctionName", "${var.project}-${n}"]]

  base_widgets = [
    {
      type   = "text"
      x      = 0
      y      = 0
      width  = 24
      height = 2
      properties = {
        markdown = "# AI Security Analyst - Platform Health\nIngestion -> ML scoring -> vector KB -> guardrailed agent -> API + alerting. Metrics across all compute, the API, event routing, and storage."
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 2
      width  = 12
      height = 6
      properties = {
        title   = "Lambda Invocations (Sum)"
        region  = var.region
        view    = "timeSeries"
        stat    = "Sum"
        period  = 300
        metrics = local.invocation_metrics
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 2
      width  = 12
      height = 6
      properties = {
        title   = "Lambda Errors (Sum)"
        region  = var.region
        view    = "timeSeries"
        stat    = "Sum"
        period  = 300
        metrics = local.error_metrics
        yAxis   = { left = { min = 0 } }
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 8
      width  = 12
      height = 6
      properties = {
        title   = "Lambda Duration p99 (ms) - critical functions"
        region  = var.region
        view    = "timeSeries"
        stat    = "p99"
        period  = 300
        metrics = local.duration_metrics
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 8
      width  = 12
      height = 6
      properties = {
        title  = "Alerting rule firings"
        region = var.region
        view   = "timeSeries"
        stat   = "Sum"
        period = 300
        metrics = [
          ["AWS/Events", "Invocations", "RuleName", local.guardduty_rule],
          ["AWS/Events", "Invocations", "RuleName", local.securityhub_rule],
          ["AWS/Events", "FailedInvocations", "RuleName", local.guardduty_rule],
          ["AWS/Events", "FailedInvocations", "RuleName", local.securityhub_rule],
        ]
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 14
      width  = 12
      height = 6
      properties = {
        title  = "Chat API requests + errors (Sum)"
        region = var.region
        view   = "timeSeries"
        stat   = "Sum"
        period = 300
        metrics = [
          ["AWS/ApiGateway", "Count", "ApiId", local.chat_api_id],
          ["AWS/ApiGateway", "4xx", "ApiId", local.chat_api_id],
          ["AWS/ApiGateway", "5xx", "ApiId", local.chat_api_id],
        ]
      }
    },
    {
      type   = "metric"
      x      = 12
      y      = 14
      width  = 12
      height = 6
      properties = {
        title  = "Chat API latency (ms)"
        region = var.region
        view   = "timeSeries"
        period = 300
        metrics = [
          ["AWS/ApiGateway", "Latency", "ApiId", local.chat_api_id, { stat = "p50" }],
          ["AWS/ApiGateway", "Latency", "ApiId", local.chat_api_id, { stat = "p99" }],
          ["AWS/ApiGateway", "IntegrationLatency", "ApiId", local.chat_api_id, { stat = "p99" }],
        ]
      }
    },
    {
      type   = "metric"
      x      = 0
      y      = 20
      width  = 12
      height = 6
      properties = {
        title  = "DynamoDB - conversation history"
        region = var.region
        view   = "timeSeries"
        stat   = "Sum"
        period = 300
        metrics = [
          ["AWS/DynamoDB", "ConsumedReadCapacityUnits", "TableName", local.conversation_table],
          ["AWS/DynamoDB", "ConsumedWriteCapacityUnits", "TableName", local.conversation_table],
          ["AWS/DynamoDB", "ThrottledRequests", "TableName", local.conversation_table],
        ]
      }
    },
  ]

  aurora_widget = var.kb_cluster_identifier == "" ? [] : [
    {
      type   = "metric"
      x      = 12
      y      = 20
      width  = 12
      height = 6
      properties = {
        title  = "Aurora KB - Serverless capacity (ACU) + connections"
        region = var.region
        view   = "timeSeries"
        period = 300
        metrics = [
          ["AWS/RDS", "ServerlessDatabaseCapacity", "DBClusterIdentifier", var.kb_cluster_identifier, { stat = "Average" }],
          ["AWS/RDS", "DatabaseConnections", "DBClusterIdentifier", var.kb_cluster_identifier, { stat = "Sum" }],
        ]
      }
    }
  ]

  all_widgets = concat(local.base_widgets, local.aurora_widget)
}

resource "aws_cloudwatch_dashboard" "platform" {
  provider = aws.security_tooling

  dashboard_name = "${var.project}-platform"
  dashboard_body = jsonencode({ widgets = local.all_widgets })
}
