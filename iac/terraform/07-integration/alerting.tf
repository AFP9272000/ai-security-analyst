# Alerting: SNS topic + EventBridge rules (in Security Tooling)
#
# SNS encryption uses the AWS-managed key alias/aws/sns, NOT the baseline
# CMK. Deliberate: a CMK on an SNS topic needs sns.amazonaws.com granted
# in the key policy (the recurring KMS-service-principal lesson - hit on
# CW Logs, EventBridge, SQS, the guardrail). For an internal alert topic
# that isn't worth the key-policy maintenance, so we use the managed key.
# Still encrypted at rest; no key-policy coupling. See ADR-0017.
#
# Two EventBridge rules on the default bus (where GuardDuty and Security
# Hub natively emit in this delegated-admin account), each filtered to
# high severity and targeting the triage Lambda.

resource "aws_sns_topic" "alerts" {
  provider = aws.security_tooling

  name              = "${var.project}-alerts"
  display_name      = "AI Sec Analyst Alerts"
  kms_master_key_id = "alias/aws/sns"
}

# Email subscription, only when an address is provided. Requires manual
# confirmation via the link AWS emails.
resource "aws_sns_topic_subscription" "email" {
  count    = var.alert_email == "" ? 0 : 1
  provider = aws.security_tooling

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# EventBridge: GuardDuty high severity (>= 7)
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

# EventBridge: Security Hub HIGH/CRITICAL
resource "aws_cloudwatch_event_rule" "securityhub_high" {
  provider = aws.security_tooling

  name        = "${var.project}-securityhub-high-sev"
  description = "HIGH/CRITICAL Security Hub findings to the triage Lambda"

  event_pattern = jsonencode({
    source      = ["aws.securityhub"]
    detail-type = ["Security Hub Findings - Imported"]
    detail = {
      findings = {
        Severity = {
          Label = ["HIGH", "CRITICAL"]
        }
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

# Let EventBridge invoke the triage Lambda
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
