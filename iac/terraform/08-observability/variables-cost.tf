# Added in the 08 apply fix. Separate file so it merges cleanly with the
# existing variables.tf (Terraform reads all *.tf in the directory).
#
# AWS allows only ONE dimensional (SERVICE) Cost Anomaly Detection monitor
# per account, and this account already has one. These two variables let
# skip creation, attach to the existing monitor, or (in a fresh
# account) create a new one.

variable "create_cost_anomaly_monitor" {
  description = <<-EOT
    Create a new SERVICE-dimension anomaly monitor. Leave false if the
    account already has a dimensional monitor (you'll hit "Limit exceeded
    on dimensional spend monitor creation"). Set true only in an account
    with no existing dimensional monitor.
  EOT
  type        = bool
  default     = false
}

variable "cost_anomaly_monitor_arn" {
  description = <<-EOT
    ARN of an EXISTING anomaly monitor to attach the email subscription
    to (used only when create_cost_anomaly_monitor = false). Leave blank
    to skip Cost Anomaly Detection here entirely (the budget remains the
    Terraform-managed cost guardrail). Find it with:
      aws ce get-anomaly-monitors \
        --query "AnomalyMonitors[*].{Name:MonitorName,Arn:MonitorArn,Dim:MonitorDimension}"
  EOT
  type        = string
  default     = ""
}
