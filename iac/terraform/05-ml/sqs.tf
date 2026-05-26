# SQS for inference Lambda trigger
#
# S3 event notifications -> SQS -> Lambda. See ADR-0012 for the trigger
# architecture rationale.
#
# REVISED v2: Dropped customer-managed CMK encryption on
# both queues. AWS-managed SSE-SQS instead. S3 service principal can't
# publish to a queue encrypted with a CMK whose policy doesn't grant
# s3.amazonaws.com and expanding the baseline KMS policy for every
# new service principal that wants to write encrypted messages doesn't
# scale. Same call we made for the EventBridge bus
#
# Messages on this queue contain only S3 event metadata (bucket, key,
# event type) - no actual finding content. The findings themselves
# remain encrypted at rest in S3 with the customer CMK.

# Dead-letter queue (DLQ)

resource "aws_sqs_queue" "inference_dlq" {
  provider = aws.security_tooling

  name                       = "${var.project}-inference-dlq"
  message_retention_seconds  = 1209600 # 14 days
  visibility_timeout_seconds = 60
  sqs_managed_sse_enabled    = true
}

# Primary queue

resource "aws_sqs_queue" "inference" {
  provider = aws.security_tooling

  name                       = "${var.project}-inference-queue"
  message_retention_seconds  = 86400 # 1 day - inference should keep up
  visibility_timeout_seconds = var.inference_sqs_visibility_timeout
  sqs_managed_sse_enabled    = true

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
