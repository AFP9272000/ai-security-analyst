output "dashboard_name" {
  description = "CloudWatch dashboard name"
  value       = aws_cloudwatch_dashboard.platform.dashboard_name
}

output "dashboard_url" {
  description = "Console URL for the platform dashboard"
  value       = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.platform.dashboard_name}"
}

output "lambda_error_alarm_names" {
  value = [for a in aws_cloudwatch_metric_alarm.lambda_errors : a.alarm_name]
}

output "budget_name" {
  value = aws_budgets_budget.monthly.name
}

output "anomaly_monitor_arn" {
  description = "Effective anomaly monitor ARN (created, existing, or null if CE skipped)"
  value       = local.effective_monitor_arn
}
