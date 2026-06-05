output "alert_topic_arn" {
  description = "SNS topic that receives triage alerts"
  value       = aws_sns_topic.alerts.arn
}

output "triage_lambda_name" {
  description = "Name of the triage Lambda (for direct-invoke testing)"
  value       = aws_lambda_function.triage.function_name
}

output "guardduty_rule_name" {
  value = aws_cloudwatch_event_rule.guardduty_high.name
}

output "securityhub_rule_name" {
  value = aws_cloudwatch_event_rule.securityhub_high.name
}

output "email_subscription_pending" {
  description = "Whether an email subscription was created (needs confirmation)"
  value       = var.alert_email == "" ? "none (no alert_email set)" : "check ${var.alert_email} and confirm the subscription"
}
