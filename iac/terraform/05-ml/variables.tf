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

variable "ecr_image_retention_count" {
  description = "Keep the N most recent ECR image versions; older ones are deleted by lifecycle policy."
  type        = number
  default     = 10
}

variable "model_package_group_name" {
  description = "Name of the SageMaker Model Registry package group."
  type        = string
  default     = "ai-sec-analyst-anomaly"
}
