variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_region" {
  description = "Region where the TF state bucket lives (created by 00-bootstrap)"
  type        = string
  default     = "us-east-2"
}

variable "project" {
  type    = string
  default = "ai-sec-analyst"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b"]
}

variable "workload_vpc_cidr" {
  type    = string
  default = "10.10.0.0/16"
}

variable "security_tooling_vpc_cidr" {
  type    = string
  default = "10.20.0.0/16"
}
