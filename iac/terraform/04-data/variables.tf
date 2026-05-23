variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_region" {
  type    = string
  default = "us-east-2"
}

variable "project" {
  type    = string
  default = "ai-sec-analyst"
}

variable "athena_results_lifecycle_days" {
  description = "Days before Athena query results are deleted. Results are reproducible by re-running queries."
  type        = number
  default     = 7
}

variable "enriched_findings_retention_days" {
  description = "Lifecycle transition to Glacier-IR for enriched findings older than this."
  type        = number
  default     = 90
}
