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

# Part 2 additions

variable "endpoint_enabled" {
  description = "Set true to deploy the SageMaker real-time endpoint. ~$50/month always-on at ml.t2.medium. Default false to keep cost down between demos."
  type        = bool
  default     = false
}

variable "endpoint_instance_type" {
  description = "Endpoint instance type. ml.t2.medium is the cheapest serving instance."
  type        = string
  default     = "ml.t2.medium"
}

variable "approved_model_package_arn" {
  description = "ARN of an Approved ModelPackage in the registry. Required when endpoint_enabled = true. Find it via: aws sagemaker list-model-packages --model-package-group-name ai-sec-analyst-anomaly --model-approval-status Approved"
  type        = string
  default     = ""
}

variable "inference_sqs_visibility_timeout" {
  description = "SQS visibility timeout in seconds. Should be >= Lambda timeout."
  type        = number
  default     = 90
}

variable "inference_lambda_timeout" {
  description = "Lambda timeout in seconds."
  type        = number
  default     = 60
}
