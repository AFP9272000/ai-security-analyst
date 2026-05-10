variable "region" {
  description = "Home region"
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Project name prefix"
  type        = string
  default     = "ai-sec-analyst"
}

variable "root_email" {
  description = "Base Gmail address for + aliasing (e.g. youraddress@gmail.com). All member account emails are derived as <local>+ai-sec-<account>@<domain>."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.root_email))
    error_message = "root_email must be a valid email address."
  }
}

variable "allowed_regions" {
  description = "Regions permitted by the deny-regions SCP"
  type        = list(string)
  default     = ["us-east-1", "us-east-2"]
}
