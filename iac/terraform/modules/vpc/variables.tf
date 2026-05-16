variable "name" {
  description = "VPC name. Used in resource naming and tags."
  type        = string
}

variable "cidr" {
  description = "VPC CIDR block (e.g. 10.10.0.0/16)."
  type        = string
}

variable "azs" {
  description = "Availability Zones to deploy subnets across."
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets. Empty list disables IGW and public tier."
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "CIDRs for private (app-tier) subnets."
  type        = list(string)
  default     = []
}

variable "database_subnet_cidrs" {
  description = "CIDRs for database-tier subnets. Isolated, no route to IGW."
  type        = list(string)
  default     = []
}

variable "enable_flow_logs" {
  description = "Enable VPC flow logs to CloudWatch with the project's baseline CMK."
  type        = bool
  default     = true
}

variable "flow_logs_kms_key_arn" {
  description = "KMS key for flow log encryption. Required if enable_flow_logs = true."
  type        = string
  default     = null
}

variable "flow_logs_retention_days" {
  description = "CloudWatch Logs retention in days for flow logs."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags merged with the project tag standard."
  type        = map(string)
  default     = {}
}
