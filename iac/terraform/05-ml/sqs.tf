# SQS for inference Lambda trigger
#
# S3 event notifications -> SQS -> Lambda. Why not S3 -> Lambda direct?
# - Visibility timeout handles slow endpoint responses gracefully
# - DLQ captures poisoned events for offline inspection
# - Partial batch failure semantics (batchItemFailures) prevents
#   one bad event from invalidating the whole batch
# - Decouples S3 throughput from Lambda concurrency limits

# Dead-letter queue (DLQ)

resource "aws_sqs_queue" "inference_dlq" {
  provider = aws.security_tooling

  name                       = "${var.project}-inference-dlq"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 60
  kms_master_key_id          = local.baseline_key_arns["security-tooling"]
}

# Primary queue

resource "aws_sqs_queue" "inference" {
  provider = aws.security_tooling

  name                       = "${var.project}-inference-queue"
  message_retention_seconds  = 86400 # 1 day - inference should keep up
  visibility_timeout_seconds = var.inference_sqs_visibility_timeout
  kms_master_key_id          = local.baseline_key_arns["security-tooling"]

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.inference_dlq.arn
    maxReceiveCount     = 3
  })
}

# Allow S3 to publish to this queue
data "aws_iam_policy_document" "inference_queue_policy" {
  statement {
    sid    = "AllowS3PublishFromEnrichedBucket"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.inference.arn]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [local.enriched_findings_bucket_arn]
    }
  }
}

resource "aws_sqs_queue_policy" "inference" {
  provider = aws.security_tooling

  queue_url = aws_sqs_queue.inference.id
  policy    = data.aws_iam_policy_document.inference_queue_policy.json
}

# S3 bucket notification on the enriched-findings bucket
#
# The enriched bucket lives in the same security-tooling account, so no
# cross-account permissions are needed. Filtered to enriched/ prefix to
# avoid notifications on our own scored/ writes.

resource "aws_s3_bucket_notification" "enriched_to_inference_queue" {
  provider = aws.security_tooling

  bucket = local.enriched_findings_bucket

  queue {
    queue_arn     = aws_sqs_queue.inference.arn
    events        = ["s3:ObjectCreated:*"]
    filter_prefix = "enriched/"
    filter_suffix = ".json"
  }

  depends_on = [aws_sqs_queue_policy.inference]
}
