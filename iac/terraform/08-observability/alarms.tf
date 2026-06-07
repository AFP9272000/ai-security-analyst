# CloudWatch alarms (Security Tooling)
#
# The failure conditions worth a page: any errors on the critical Lambdas,
# and 5xx on the chat API. Actions go to the alert SNS topic
# (read from 07-integration state), one place for both finding alerts
# and ops alarms. treat_missing_data = notBreaching so an idle (no-data)
# function doesn't sit in INSUFFICIENT_DATA.

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  for_each = toset(local.critical_lambdas)
  provider = aws.security_tooling

  alarm_name          = "${var.project}-${each.key}-errors"
  alarm_description   = "Errors detected on the ${each.key} Lambda"
  namespace           = "AWS/Lambda"
  metric_name         = "Errors"
  dimensions          = { FunctionName = "${var.project}-${each.key}" }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [local.alert_topic_arn]
  ok_actions    = [local.alert_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "api_5xx" {
  provider = aws.security_tooling

  alarm_name          = "${var.project}-chat-api-5xx"
  alarm_description   = "5xx responses from the chat API (integration failures, timeouts)"
  namespace           = "AWS/ApiGateway"
  metric_name         = "5xx"
  dimensions          = { ApiId = local.chat_api_id }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [local.alert_topic_arn]
  ok_actions    = [local.alert_topic_arn]
}

# Catch DLQ-style failures surfaced as EventBridge FailedInvocations on
# the alerting rules (e.g. the triage Lambda being unreachable).
resource "aws_cloudwatch_metric_alarm" "alert_rule_failures" {
  for_each = toset([local.guardduty_rule, local.securityhub_rule])
  provider = aws.security_tooling

  alarm_name          = "${each.value}-failed-invocations"
  alarm_description   = "EventBridge could not deliver findings to the triage Lambda"
  namespace           = "AWS/Events"
  metric_name         = "FailedInvocations"
  dimensions          = { RuleName = each.value }
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [local.alert_topic_arn]
}
