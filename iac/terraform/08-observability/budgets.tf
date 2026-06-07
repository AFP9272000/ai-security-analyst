# Cost controls (Management / payer account, default provider)
#
# A monthly cost budget with threshold alerts, plus Cost Anomaly
# Detection. Both notify by EMAIL directly rather than via SNS: routing
# Budgets/CE through an SNS topic requires granting budgets.amazonaws.com
# / costalerts.amazonaws.com publish rights in the topic policy (another
# service-principal coupling). Email-direct keeps it simple.

locals {
  budget_notifications = var.notification_email == "" ? [] : [
    { type = "ACTUAL", threshold = 80 },
    { type = "ACTUAL", threshold = 100 },
    { type = "FORECASTED", threshold = 100 },
  ]
}

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_limit)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  dynamic "notification" {
    for_each = local.budget_notifications
    content {
      comparison_operator        = "GREATER_THAN"
      threshold                  = notification.value.threshold
      threshold_type             = "PERCENTAGE"
      notification_type          = notification.value.type
      subscriber_email_addresses = [var.notification_email]
    }
  }
}

# Cost Anomaly Detection: a service-dimension monitor that learns normal
# spend and flags deviations. The subscription (email alert) is only
# created when an email is provided.
resource "aws_ce_anomaly_monitor" "service" {
  name              = "${var.project}-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "this" {
  count = var.notification_email == "" ? 0 : 1

  name             = "${var.project}-anomaly-subscription"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.service.arn]

  subscriber {
    type    = "EMAIL"
    address = var.notification_email
  }

  # Only alert when the anomaly's total dollar impact is meaningful.
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = ["10"]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
}
