# Model Registry, Model Package Group (in Security Tooling)
#
# Each training run produces a ModelPackage that's registered into this
# group. ModelPackages start in PendingManualApproval status; promoting
# them to Approved is the human gate before deployment to an endpoint.

resource "aws_sagemaker_model_package_group" "anomaly" {
  provider = aws.security_tooling

  model_package_group_name        = var.model_package_group_name
  model_package_group_description = "CloudTrail anomaly detection - IsolationForest model versions"
}
