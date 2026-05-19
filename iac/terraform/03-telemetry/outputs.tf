###############################################################################
# Log archive
###############################################################################

output "log_archive_bucket_name" {
  value = aws_s3_bucket.log_archive.id
}

output "log_archive_bucket_arn" {
  value = aws_s3_bucket.log_archive.arn
}

###############################################################################
# CloudTrail
###############################################################################

output "cloudtrail_arn" {
  value = aws_cloudtrail.org_trail.arn
}

output "cloudtrail_name" {
  value = aws_cloudtrail.org_trail.name
}

###############################################################################
# GuardDuty
###############################################################################

output "guardduty_detector_id" {
  value = aws_guardduty_detector.main.id
}

output "guardduty_admin_account_id" {
  value = local.security_tooling_id
}

output "guardduty_member_accounts" {
  description = "Member accounts enrolled in this GuardDuty detector"
  value = [
    aws_guardduty_member.log_archive.account_id,
    aws_guardduty_member.workload.account_id,
  ]
}
