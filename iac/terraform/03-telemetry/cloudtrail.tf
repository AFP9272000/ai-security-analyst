# Organization-wide CloudTrail (in Management account)
#
# Multi-region, includes global service events (IAM, CloudFront, etc.),
# log file validation enabled. Delivers to the Log Archive bucket via
# the cross-account bucket policy set above.
#
# Bucket policy uses depends_on indirectly via the bucket reference.

resource "aws_cloudtrail" "org_trail" {
  name           = "${var.project}-org-trail"
  s3_bucket_name = aws_s3_bucket.log_archive.id

  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true
  enable_logging                = true

  # CloudTrail uses the Management account's default key for log file
  # encryption when no KMS key is specified, but for explicit control:
  # do NOT set kms_key_id here because the trail writes to a bucket
  # that's already KMS-encrypted with the log-archive baseline key.
  # Specifying a Management-account key here would require cross-account
  # grants. Bucket-level SSE-KMS is sufficient.

  # Capture data events for S3 object reads/writes and Lambda invocations
  # in the workload account for future ML training data.
  advanced_event_selector {
    name = "Management and S3 data events"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  advanced_event_selector {
    name = "S3 object events"

    field_selector {
      field  = "eventCategory"
      equals = ["Data"]
    }
    field_selector {
      field  = "resources.type"
      equals = ["AWS::S3::Object"]
    }
  }

  depends_on = [aws_s3_bucket_policy.log_archive]
}
