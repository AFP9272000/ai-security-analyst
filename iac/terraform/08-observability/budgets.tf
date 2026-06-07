# Cost controls (Management / payer account, default provider)
#
# A monthly cost budget with threshold alerts, plus optional Cost Anomaly
# Detection. Both notify by EMAIL directly rather than via SNS (avoids a
# topic-policy service-principal grant).
#
# Anomaly Detection note: AWS allows only ONE dimensional (SERVICE) spend
# monitor per account, and AWS often auto-creates a default one. So the
# monitor here is OPTIONAL:
#   - create_cost_anomaly_monitor = false (default): don't create one.
#     If cost_anomaly_monitor_arn is set, attach a subscription to that
#     existing monitor; otherwise skip CE entirely (the budget is the
#     Terraform-managed guardrail).
#   - create_cost_anomaly_monitor = true: create a new monitor (only
#     works in an account with no existing dimensional monitor).

locals {
  budget_notifications = var.notification_email == "" ? [] : [
    { type = "ACTUAL", threshold = 80 },
    { type = "ACTUAL", threshold = 100 },
    { type = "FORECASTED", threshold = 100 },
  ]

  # Resolve which monitor (if any) the subscription should target.
  effective_monitor_arn = var.create_cost_anomaly_monitor ? one(aws_ce_anomaly_monitor.service[*].arn) : (var.cost_anomaly_monitor_arn == "" ? null : var.cost_anomaly_monitor_arn)

  create_anomaly_subscription = var.notification_email != "" && local.effective_monitor_arn != null
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

# Optional: create a new SERVICE-dimension monitor (only for accounts
# that don't already have one).
resource "aws_ce_anomaly_monitor" "service" {
  count = var.create_cost_anomaly_monitor ? 1 : 0

  name              = "${var.project}-anomaly-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

# Subscription on the effective monitor (created or existing), when an
# email is set and a monitor ARN is available.
resource "aws_ce_anomaly_subscription" "this" {
  count = local.create_anomaly_subscription ? 1 : 0

  name             = "${var.project}-anomaly-subscription"
  frequency        = "DAILY"
  monitor_arn_list = [local.effective_monitor_arn]

  subscriber {
    type    = "EMAIL"
    address = var.notification_email
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      values        = ["10"]
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
}
