# ECR repository (in Security Tooling)
#
# Holds the anomaly-model container image used by both SageMaker training
# jobs and the eventual inference endpoint. Image scanning enabled,
# lifecycle keeps the N most recent versions.

resource "aws_ecr_repository" "anomaly_model" {
  provider = aws.security_tooling

  name                 = "${var.project}-anomaly-model"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "KMS"
    kms_key         = local.baseline_key_arns["security-tooling"]
  }
}

resource "aws_ecr_lifecycle_policy" "anomaly_model" {
  provider = aws.security_tooling

  repository = aws_ecr_repository.anomaly_model.name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last ${var.ecr_image_retention_count} images, expire older untagged"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = var.ecr_image_retention_count
      }
      action = {
        type = "expire"
      }
    }]
  })
}
