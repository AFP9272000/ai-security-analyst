# ECR

output "ecr_repository_url" {
  description = "Push container images here"
  value       = aws_ecr_repository.anomaly_model.repository_url
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
