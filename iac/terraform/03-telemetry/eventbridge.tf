# EventBridge (in Security Tooling)
#
# Custom bus for security findings + rules routing GuardDuty and
# Security Hub events to a CloudWatch Log group as a placeholder target.
#
# swaps the CW Logs target for the enricher Lambda, with the
# inference Lambda subscribed in parallel.
#
# REVISED v2: Dropped kms_key_identifier from the event bus.
# The baseline KMS key policy doesn't grant events.amazonaws.com, and
# rather than expanding that policy further, the bus uses AWS-managed
# encryption (still SSE-KMS, just with an AWS-owned key). The log group
# keeps the customer-managed baseline CMK because the log policy already
# permits logs.amazonaws.com.

resource "aws_cloudwatch_event_bus" "security_findings" {
  provider = aws.security_tooling

  name = "${var.project}-security-findings"
}

# Placeholder target: CloudWatch Log group

resource "aws_cloudwatch_log_group" "findings_placeholder" {
  provider = aws.security_tooling

  name              = "/aws/events/${var.project}-security-findings"
  retention_in_days = 30
  kms_key_id        = local.baseline_key_arns["security-tooling"]
}

# EventBridge needs explicit resource policy on the log group to deliver.
data "aws_iam_policy_document" "findings_log_group" {
  statement {
    sid    = "AllowEventBridgeDelivery"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "delivery.logs.amazonaws.com"]
    }

    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]

    resources = [
      "${aws_cloudwatch_log_group.findings_placeholder.arn}:*",
    ]
  }
}

resource "aws_cloudwatch_log_resource_policy" "findings" {
  provider = aws.security_tooling

  policy_name     = "${var.project}-findings-eventbridge-delivery"
  policy_document = data.aws_iam_policy_document.findings_log_group.json
}

# Rules

# Rule 1: GuardDuty findings on the default bus -> forward to custom bus
resource "aws_cloudwatch_event_rule" "guardduty_to_custom" {
  provider = aws.security_tooling

  name        = "${var.project}-guardduty-forward"
  description = "Forward all GuardDuty findings to the custom security bus"

  event_pattern = jsonencode({
    source        = ["aws.guardduty"]
    "detail-type" = ["GuardDuty Finding"]
  })
}

resource "aws_cloudwatch_event_target" "guardduty_to_custom" {
  provider = aws.security_tooling

  rule = aws_cloudwatch_event_rule.guardduty_to_custom.name
  arn  = aws_cloudwatch_event_bus.security_findings.arn

  role_arn = aws_iam_role.eventbridge_forwarder.arn
}

# Rule 2: Security Hub findings on the default bus -> forward to custom bus
resource "aws_cloudwatch_event_rule" "securityhub_to_custom" {
  provider = aws.security_tooling

  name        = "${var.project}-securityhub-forward"
  description = "Forward Security Hub findings to the custom security bus"

  event_pattern = jsonencode({
    source        = ["aws.securityhub"]
    "detail-type" = ["Security Hub Findings - Imported"]
  })
}

resource "aws_cloudwatch_event_target" "securityhub_to_custom" {
  provider = aws.security_tooling

  rule = aws_cloudwatch_event_rule.securityhub_to_custom.name
  arn  = aws_cloudwatch_event_bus.security_findings.arn

  role_arn = aws_iam_role.eventbridge_forwarder.arn
}

# Rule 3: On the CUSTOM bus, capture everything to the placeholder log group
resource "aws_cloudwatch_event_rule" "custom_bus_to_logs" {
  provider = aws.security_tooling

  name           = "${var.project}-findings-to-logs"
  description    = "Mirror all findings on the custom bus to CloudWatch Logs (Phase 4 swaps for Lambda)"
  event_bus_name = aws_cloudwatch_event_bus.security_findings.name

  event_pattern = jsonencode({
    source = [{ exists = true }]
  })
}

resource "aws_cloudwatch_event_target" "custom_bus_to_logs" {
  provider = aws.security_tooling

  rule           = aws_cloudwatch_event_rule.custom_bus_to_logs.name
  event_bus_name = aws_cloudwatch_event_bus.security_findings.name
  arn            = aws_cloudwatch_log_group.findings_placeholder.arn
}

# IAM role for EventBridge cross-bus forwarding

resource "aws_iam_role" "eventbridge_forwarder" {
  provider = aws.security_tooling

  name = "${var.project}-eventbridge-forwarder"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "eventbridge_forwarder" {
  provider = aws.security_tooling

  role = aws_iam_role.eventbridge_forwarder.id
  name = "put-events-to-custom-bus"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "events:PutEvents"
      Resource = aws_cloudwatch_event_bus.security_findings.arn
    }]
  })
}
