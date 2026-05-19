# Log archive 

output "log_archive_bucket_name" {
  value = aws_s3_bucket.log_archive.id
}

output "log_archive_bucket_arn" {
  value = aws_s3_bucket.log_archive.arn
}

# CloudTrail 

output "cloudtrail_arn" {
  value = aws_cloudtrail.org_trail.arn
}

output "cloudtrail_name" {
  value = aws_cloudtrail.org_trail.name
}

# GuardDuty (Part 1)
#
# Note: member account enrollment is auto-managed by org config, not
# explicit aws_guardduty_member resources. Use the AWS CLI to list
# current members at runtime:
#   aws guardduty list-members --detector-id <DETECTOR_ID> --profile security-tooling

output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id
}

output "guardduty_admin_account_id" {
  value = local.security_tooling_id
}

# Security Hub 

output "securityhub_account_id" {
  value = aws_securityhub_account.main.id
}

output "securityhub_standards_subscribed" {
  value = [
    aws_securityhub_standards_subscription.afsbp.standards_arn,
    aws_securityhub_standards_subscription.cis.standards_arn,
  ]
}

# EventBridge 

output "security_findings_bus_name" {
  value = aws_cloudwatch_event_bus.security_findings.name
}

output "security_findings_bus_arn" {
  value = aws_cloudwatch_event_bus.security_findings.arn
}

output "findings_placeholder_log_group" {
  description = "Where security findings land until Phase 4 wires Lambda consumers"
  value       = aws_cloudwatch_log_group.findings_placeholder.name
}

# Config 

output "config_aggregator_arn" {
  value = aws_config_configuration_aggregator.org.arn
}

output "config_logs_bucket_name" {
  value = aws_s3_bucket.config_logs.id
}

output "config_recorder_names" {
  value = {
    management       = aws_config_configuration_recorder.mgmt.name
    log-archive      = aws_config_configuration_recorder.log_archive.name
    security-tooling = aws_config_configuration_recorder.security_tooling.name
    workload         = aws_config_configuration_recorder.workload.name
  }
}
