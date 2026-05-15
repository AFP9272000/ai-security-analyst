variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "ai-sec-analyst"
}

variable "github_org" {
  type    = string
  default = "AFP9272000"
}

variable "github_repo" {
  type    = string
  default = "ai-security-analyst"
}

variable "github_branch" {
  type    = string
  default = "main"
}

variable "codeconnections_arn" {
  description = "ARN of the CodeStar/CodeConnections connection to GitHub (created manually). Passed via TF_VAR_codeconnections_arn."
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^arn:aws:(codestar-connections|codeconnections):", var.codeconnections_arn))
    error_message = "Must be a CodeStar or CodeConnections ARN."
  }
}

variable "tf_version" {
  type    = string
  default = "1.7.5"
}
