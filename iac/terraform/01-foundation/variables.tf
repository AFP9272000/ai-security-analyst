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

# Identity Center user 

variable "sso_username" {
  description = "Identity Center login username (no spaces; lowercase recommended)"
  type        = string
  default     = "addison.p"
}

variable "sso_display_name" {
  description = "Display name shown in Identity Center console"
  type        = string
  default     = "Addison P."
}

variable "sso_given_name" {
  description = "First name (Identity Store name.given_name)"
  type        = string
  default     = "Addison"
}

variable "sso_family_name" {
  description = "Last name (Identity Store name.family_name)"
  type        = string
  default     = "P"
}
