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

variable "log_archive_retention_days" {
  description = "Object Lock retention period in days for CloudTrail logs."
  type        = number
  default     = 365
}

variable "log_archive_object_lock_mode" {
  description = "GOVERNANCE allows privileged delete; COMPLIANCE blocks all delete until retention expires. GOVERNANCE for portfolio destroy-friendliness."
  type        = string
  default     = "GOVERNANCE"
  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.log_archive_object_lock_mode)
    error_message = "Must be GOVERNANCE or COMPLIANCE."
  }
}

variable "guardduty_finding_frequency" {
  description = "How often GuardDuty publishes findings to CloudWatch/EventBridge."
  type        = string
  default     = "FIFTEEN_MINUTES"
  validation {
    condition     = contains(["FIFTEEN_MINUTES", "ONE_HOUR", "SIX_HOURS"], var.guardduty_finding_frequency)
    error_message = "Must be FIFTEEN_MINUTES, ONE_HOUR, or SIX_HOURS."
  }
}
