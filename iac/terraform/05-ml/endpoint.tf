# SageMaker real-time endpoint (in Security Tooling)
#
# ALL gated behind var.endpoint_enabled. Setting endpoint_enabled = false
# tears down the endpoint without touching the model package or pipeline.
# Cost: ~$50/month when up at ml.t2.medium, $0 when down.
#
# Workflow to deploy:
#   1. Run the pipeline (scripts/run_pipeline.py execute)
#   2. Wait for pipeline to register a ModelPackage in PendingManualApproval
#   3. Manually approve the ModelPackage:
#        aws sagemaker update-model-package \
#          --model-package-arn <arn> \
#          --model-approval-status Approved
#   4. Set endpoint_enabled = true AND approved_model_package_arn = <arn>
#   5. Terraform apply
#
# Endpoint runs in VPC mode (security-tooling private subnets) so that
# the inference Lambda can reach it via the sagemaker.runtime VPC
# interface endpoint provisioned.

resource "aws_sagemaker_model" "anomaly" {
  count    = var.endpoint_enabled ? 1 : 0
  provider = aws.security_tooling

  name               = "${var.project}-anomaly-${formatdate("YYYYMMDD-hhmm", timestamp())}"
  execution_role_arn = aws_iam_role.sagemaker_execution.arn

  primary_container {
    model_package_name = var.approved_model_package_arn
  }

  vpc_config {
    subnets            = local.security_tooling_vpc_subnets
    security_group_ids = [local.security_tooling_endpoint_sg]
  }

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [name]
  }
}

resource "aws_sagemaker_endpoint_configuration" "anomaly" {
  count    = var.endpoint_enabled ? 1 : 0
  provider = aws.security_tooling

  name = "${var.project}-anomaly-endpoint-config-${formatdate("YYYYMMDD-hhmm", timestamp())}"

  production_variants {
    variant_name           = "primary"
    model_name             = aws_sagemaker_model.anomaly[0].name
    initial_instance_count = 1
    instance_type          = var.endpoint_instance_type
    initial_variant_weight = 1
  }

  data_capture_config {
    enable_capture              = true
    initial_sampling_percentage = 100
    destination_s3_uri          = "s3://${aws_s3_bucket.model_artifacts.id}/data-capture/"
    kms_key_arn                 = local.baseline_key_arns["security-tooling"]

    capture_options {
      capture_mode = "Input"
    }
    capture_options {
      capture_mode = "Output"
    }
  }

  kms_key_arn = local.baseline_key_arns["security-tooling"]

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [name]
  }
}

resource "aws_sagemaker_endpoint" "anomaly" {
  count    = var.endpoint_enabled ? 1 : 0
  provider = aws.security_tooling

  name                 = "${var.project}-anomaly-endpoint"
  endpoint_config_name = aws_sagemaker_endpoint_configuration.anomaly[0].name
}
