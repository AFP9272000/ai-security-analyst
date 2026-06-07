# Alerting: SNS topic + EventBridge rules + dedup table (Security Tooling)
#
# SNS encryption uses the AWS-managed key alias/aws/sns, NOT the baseline
# CMK (recurring KMS-service-principal lesson).
#
# DEDUP (ADR-0019): Security Hub and GuardDuty re-import the same finding
# repeatedly; each re-import fires the rule. Two countermeasures:
#   - The triage Lambda dedups by finding id via a conditional write to
#     the dynamodb table below (one alert per finding per TTL window).
#   - The Security Hub rule is narrowed to Workflow.Status=NEW +
#     RecordState=ACTIVE so stale/resolved churn doesn't even arrive.

resource "aws_sns_topic" "alerts" {
  provider = aws.security_tooling

  name              = "${var.project}-alerts"
  display_name      = "AI Sec Analyst Alerts"
  kms_master_key_id = "alias/aws/sns"
}

resource "aws_sns_topic_subscription" "email" {
  count    = var.alert_email == "" ? 0 : 1
  provider = aws.security_tooling

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Alert deduplication table
# One row per alerted finding id, auto-expiring via TTL. The triage Lambda
# conditional-writes here: a successful write means "new, alert"; a
# conditional failure means "already alerted, suppress".
resource "aws_dynamodb_table" "alert_dedup" {
  provider = aws.security_tooling

  name         = "${var.project}-alert-dedup"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "finding_id"

  attribute {
    name = "finding_id"
    type = "S"
  }

  ttl {
    attribute_name = "ttl"
    enabled        = true
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = local.security_tooling_kms_arn
  }
}

# EventBridge: GuardDuty high severity (>= 7)
# Re-fires of the same finding are handled by the Lambda's id dedup.
resource "aws_cloudwatch_event_rule" "guardduty_high" {
  provider = aws.security_tooling

  name        = "${var.project}-guardduty-high-sev"
  description = "High-severity GuardDuty findings to the triage Lambda"

  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      severity = [{ numeric = [">=", 7] }]
    }
  })
}

resource "aws_cloudwatch_event_target" "guardduty_high" {
  provider = aws.security_tooling

  rule      = aws_cloudwatch_event_rule.guardduty_high.name
  target_id = "triage-lambda"
  arn       = aws_lambda_function.triage.arn
}

# EventBridge: Security Hub HIGH/CRITICAL, NEW + ACTIVE only
# Narrowed to genuinely-new active findings. This cuts the bulk of the
# re-import noise before it reaches the Lambda; the Lambda's id dedup
# handles any remaining repeats.
resource "aws_cloudwatch_event_rule" "securityhub_high" {
  provider = aws.security_tooling

  name        = "${var.project}-securityhub-high-sev"
  description = "New, active HIGH/CRITICAL Security Hub findings to the triage Lambda"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["HIGH", "CRITICAL"]
        }
        Workflow = {
          Status = ["NEW"]
        }
        RecordState = ["ACTIVE"]
      }
    }
  })
}

resource "aws_cloudwatch_event_target" "securityhub_high" {
  provider = aws.security_tooling

  rule      = aws_cloudwatch_event_rule.securityhub_high.name
  target_id = "triage-lambda"
  arn       = aws_lambda_function.triage.arn
}

#  Let EventBridge invoke the triage Lambda
resource "aws_lambda_permission" "events_guardduty" {
  provider = aws.security_tooling

  statement_id  = "AllowEventBridgeGuardDuty"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.triage.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.guardduty_high.arn
}

resource "aws_lambda_permission" "events_securityhub" {
  provider = aws.security_tooling

  statement_id  = "AllowEventBridgeSecurityHub"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.triage.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.securityhub_high.arn
}
