# ECR

output "ecr_repository_url" {
  value = aws_ecr_repository.anomaly_model.repository_url
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.anomaly_model.arn
}

# S3

output "training_data_bucket_name" {
  value = aws_s3_bucket.training_data.id
}

output "training_data_bucket_arn" {
  value = aws_s3_bucket.training_data.arn
}

output "model_artifacts_bucket_name" {
  value = aws_s3_bucket.model_artifacts.id
}

output "model_artifacts_bucket_arn" {
  value = aws_s3_bucket.model_artifacts.arn
}

# IAM 

output "sagemaker_execution_role_arn" {
  value = aws_iam_role.sagemaker_execution.arn
}

# Model Registry 

output "model_package_group_name" {
  value = aws_sagemaker_model_package_group.anomaly.model_package_group_name
}

output "model_package_group_arn" {
  value = aws_sagemaker_model_package_group.anomaly.arn
}

# SQS + Inference Lambda 

output "inference_queue_arn" {
  value = aws_sqs_queue.inference.arn
}

output "inference_dlq_arn" {
  value = aws_sqs_queue.inference_dlq.arn
}

output "inference_lambda_arn" {
  value = aws_lambda_function.inference.arn
}

output "inference_lambda_name" {
  value = aws_lambda_function.inference.function_name
}

output "inference_log_group_name" {
  value = aws_cloudwatch_log_group.inference.name
}

# Scored findings 

output "scored_findings_table_name" {
  value = aws_glue_catalog_table.scored_findings.name
}

# Endpoint 

output "endpoint_enabled" {
  value = var.endpoint_enabled
}

output "endpoint_name" {
  value = var.endpoint_enabled ? aws_sagemaker_endpoint.anomaly[0].name : ""
}

output "endpoint_arn" {
  value = var.endpoint_enabled ? aws_sagemaker_endpoint.anomaly[0].arn : ""
}
