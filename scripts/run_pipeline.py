"""
Helper script to register and execute the anomaly detection pipeline.

Usage (from repo root):

    # Register the pipeline (creates it in AWS, idempotent on re-run)
    python scripts/run_pipeline.py register

    # Trigger an execution
    python scripts/run_pipeline.py execute

    # Check status of recent executions
    python scripts/run_pipeline.py status

Requires:
    pip install sagemaker boto3
    AWS_PROFILE=security-tooling
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

import boto3

REPO_ROOT = Path(__file__).resolve().parent.parent
# Renamed from pipelines/sagemaker/ to avoid shadowing the SageMaker SDK
sys.path.insert(0, str(REPO_ROOT / "pipelines" / "anomaly"))


PROJECT = "ai-sec-analyst"
REGION = os.environ.get("AWS_REGION", "us-east-1")
PIPELINE_NAME = f"{PROJECT}-anomaly-pipeline"
MODEL_PACKAGE_GROUP = f"{PROJECT}-anomaly"


def _resolve_execution_role() -> str:
    """Get the SageMaker execution role ARN from this account."""
    iam = boto3.client("iam")
    role = iam.get_role(RoleName=f"{PROJECT}-sagemaker-execution")
    return role["Role"]["Arn"]


def _resolve_account_id() -> str:
    sts = boto3.client("sts")
    return sts.get_caller_identity()["Account"]


def _ecr_image_uri() -> str:
    acct = _resolve_account_id()
    return f"{acct}.dkr.ecr.{REGION}.amazonaws.com/{PROJECT}-anomaly-model:latest"


def _training_data_s3_uri() -> str:
    acct = _resolve_account_id()
    return f"s3://{PROJECT}-training-data-{acct}/raw/"


def register():
    """Build the pipeline definition and upsert it into SageMaker."""
    from anomaly_pipeline import build_pipeline_definition

    definition = build_pipeline_definition()

    role_arn = _resolve_execution_role()
    image_uri = _ecr_image_uri()
    training_data_uri = _training_data_s3_uri()

    sm = boto3.client("sagemaker", region_name=REGION)

    try:
        sm.describe_pipeline(PipelineName=PIPELINE_NAME)
        print(f"Updating existing pipeline {PIPELINE_NAME}")
        sm.update_pipeline(
            PipelineName=PIPELINE_NAME,
            PipelineDefinition=json.dumps(definition),
            RoleArn=role_arn,
        )
    except sm.exceptions.ResourceNotFound:
        print(f"Creating new pipeline {PIPELINE_NAME}")
        sm.create_pipeline(
            PipelineName=PIPELINE_NAME,
            PipelineDefinition=json.dumps(definition),
            RoleArn=role_arn,
            Tags=[
                {"Key": "Project", "Value": PROJECT},
                {"Key": "Layer", "Value": "05-ml"},
                {"Key": "ManagedBy", "Value": "manual-script"},
            ],
        )
    print(f"Pipeline registered. Default params: image_uri={image_uri}, "
          f"role={role_arn}, training_data={training_data_uri}, "
          f"model_package_group={MODEL_PACKAGE_GROUP}")


def execute():
    """Start a pipeline execution."""
    role_arn = _resolve_execution_role()
    image_uri = _ecr_image_uri()
    training_data_uri = _training_data_s3_uri()

    sm = boto3.client("sagemaker", region_name=REGION)
    response = sm.start_pipeline_execution(
        PipelineName=PIPELINE_NAME,
        PipelineParameters=[
            {"Name": "ProjectName", "Value": PROJECT},
            {"Name": "ImageUri", "Value": image_uri},
            {"Name": "ExecutionRoleArn", "Value": role_arn},
            {"Name": "TrainingDataUri", "Value": training_data_uri},
            {"Name": "ModelPackageGroupName", "Value": MODEL_PACKAGE_GROUP},
        ],
    )
    print(f"Started execution: {response['PipelineExecutionArn']}")
    print("Watch progress in the SageMaker Studio console or:")
    print(f"  aws sagemaker describe-pipeline-execution "
          f"--pipeline-execution-arn {response['PipelineExecutionArn']}")


def status():
    """List recent executions."""
    sm = boto3.client("sagemaker", region_name=REGION)
    response = sm.list_pipeline_executions(
        PipelineName=PIPELINE_NAME,
        MaxResults=10,
    )
    for exec_summary in response.get("PipelineExecutionSummaries", []):
        print(f"  {exec_summary['StartTime'].isoformat()}  "
              f"{exec_summary['PipelineExecutionStatus']}  "
              f"{exec_summary['PipelineExecutionArn'].split('/')[-1]}")


def main():
    parser = argparse.ArgumentParser(description="Manage the anomaly detection pipeline.")
    parser.add_argument("command", choices=["register", "execute", "status"])
    args = parser.parse_args()

    if args.command == "register":
        register()
    elif args.command == "execute":
        execute()
    elif args.command == "status":
        status()


if __name__ == "__main__":
    main()
