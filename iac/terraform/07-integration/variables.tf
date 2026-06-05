variable "region" {
  description = "Primary region for resources"
  type        = string
  default     = "us-east-1"
}

variable "state_region" {
  description = "Region of the Terraform state backend"
  type        = string
  default     = "us-east-2"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "ai-sec-analyst"
}

variable "alert_email" {
  description = <<-EOT
    Email address to subscribe to the alert topic. Leave blank ("") to
    deploy without an email subscription (e.g. to use Slack only). When
    set, you must confirm the subscription via the link AWS emails you
    before alerts are delivered.
  EOT
  type        = string
  default     = "addisonpirlo2@gmail.com"
}

variable "enable_agent_triage" {
  description = <<-EOT
    When true, the triage Lambda asks the Bedrock agent to assess each
    high-severity finding and includes the summary in the alert. When
    false, alerts carry only the raw finding details. Either way the
    alert always sends (the agent call is fail-safe).
  EOT
  type        = bool
  default     = true
}

variable "agent_alias_id" {
  description = <<-EOT
    Agent alias the triage Lambda invokes. Defaults to TSTALIASID (the
    working draft) for the same reason the Part 3 orchestrator does: it
    always reflects the latest prepared agent. Switch to the published
    `live` alias id once you cut a stable version (see ADR-0016/0017).
  EOT
  type        = string
  default     = "TSTALIASID"
}

variable "slack_webhook_ssm_param" {
  description = <<-EOT
    Optional. Name of an SSM Parameter Store SecureString holding a Slack
    incoming-webhook URL. Leave blank to disable Slack. The parameter
    must live under /${"$"}{project}/ for the Lambda's IAM scope to cover it
    (e.g. /ai-sec-analyst/slack-webhook).
  EOT
  type        = string
  default     = ""
}
