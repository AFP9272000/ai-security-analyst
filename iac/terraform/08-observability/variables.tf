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

variable "monthly_budget_limit" {
  description = "Monthly cost budget for the project, in USD"
  type        = number
  default     = 50
}

variable "notification_email" {
  description = <<-EOT
    Email for budget threshold alerts and cost anomaly notifications.
    Leave blank ("") to deploy the budget/monitor without email
    subscriptions (the budget still tracks spend; no anomaly subscription
    is created). These notify by email directly (not via SNS) to avoid a
    topic-policy service-principal grant.
  EOT
  type        = string
  default     = "addisonpirlo2@gmail.com"
}

variable "kb_cluster_identifier" {
  description = <<-EOT
    Optional. The Aurora KB cluster identifier (DBClusterIdentifier), to
    add a Serverless ACU widget to the dashboard. Leave blank to omit the
    widget. Find it with:
      aws rds describe-db-clusters --region us-east-1 \
        --query "DBClusters[?contains(DBClusterIdentifier,'ai-sec-analyst')].DBClusterIdentifier"
  EOT
  type        = string
  default     = ""
}
