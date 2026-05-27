"""
SageMaker Pipeline definition for the CloudTrail anomaly detection model.

This script BUILDS the pipeline JSON. The pipeline itself is registered
in AWS via Terraform (iac/terraform/05-ml/pipeline.tf) which calls this
script's exported pipeline JSON.

To regenerate the pipeline JSON locally:
    python pipelines/sagemaker/anomaly_pipeline.py > pipelines/sagemaker/anomaly_pipeline.json

Pipeline steps:
    1. Preprocess: ProcessingStep that extracts CloudTrail data from
       Athena, writes train/val parquet to S3
    2. Train: TrainingStep using our custom container
    3. Evaluate: ProcessingStep that scores the model against a held-out
       validation set, writes metrics JSON
    4. Conditional Register: RegisterModel step that fires only if the
       model's anomaly-rate metric falls within an acceptable range.
       Created with ModelApprovalStatus="PendingManualApproval" - the
       human gate before promotion.
"""
from __future__ import annotations

import json
import os
import sys

# This script is meant to be runnable both inside SageMaker Studio and
# locally. Import the SageMaker SDK lazily so the module can be imported
# for inspection without the SDK installed.
def build_pipeline_definition() -> dict:
    """Build the pipeline definition and return it as a dict."""
    try:
        import sagemaker
        from sagemaker.estimator import Estimator
        from sagemaker.inputs import TrainingInput
        from sagemaker.model_metrics import MetricsSource, ModelMetrics
        from sagemaker.processing import (
            ProcessingInput,
            ProcessingOutput,
            ScriptProcessor,
        )
        from sagemaker.workflow.condition_step import ConditionStep
        from sagemaker.workflow.conditions import ConditionLessThanOrEqualTo
        from sagemaker.workflow.functions import JsonGet
        from sagemaker.workflow.parameters import (
            ParameterFloat,
            ParameterInteger,
            ParameterString,
        )
        from sagemaker.workflow.pipeline import Pipeline
        from sagemaker.workflow.properties import PropertyFile
        from sagemaker.workflow.step_collections import RegisterModel
        from sagemaker.workflow.steps import ProcessingStep, TrainingStep
    except ImportError:
        print("sagemaker SDK not installed; install with: pip install sagemaker",
              file=sys.stderr)
        raise

    # Pipeline parameters; can be overridden at execution time
    project = ParameterString(name="ProjectName", default_value="ai-sec-analyst")
    instance_type = ParameterString(
        name="ProcessingInstanceType",
        default_value="ml.t3.medium",
    )
    train_instance_type = ParameterString(
        name="TrainingInstanceType",
        default_value="ml.m5.large",
    )
    contamination = ParameterFloat(name="Contamination", default_value=0.01)
    n_estimators = ParameterInteger(name="NEstimators", default_value=100)
    image_uri = ParameterString(name="ImageUri")
    role_arn = ParameterString(name="ExecutionRoleArn")
    training_data_uri = ParameterString(name="TrainingDataUri")
    model_package_group = ParameterString(name="ModelPackageGroupName")
    max_anomaly_rate = ParameterFloat(
        name="MaxAcceptableAnomalyRate",
        default_value=0.05,
    )

    # PREPROCESSING step
    # The preprocessor's image_uri is the same as training - we reuse our
    # custom container for both since both need pandas + pyarrow + sklearn
    preprocessor = ScriptProcessor(
        image_uri=image_uri,
        command=["python"],
        instance_type=instance_type,
        instance_count=1,
        role=role_arn,
        base_job_name="ai-sec-analyst-preprocess",
    )

    step_preprocess = ProcessingStep(
        name="Preprocess",
        processor=preprocessor,
        inputs=[
            ProcessingInput(
                source=training_data_uri,
                destination="/opt/ml/processing/input",
                input_name="raw",
            ),
        ],
        outputs=[
            ProcessingOutput(
                output_name="train",
                source="/opt/ml/processing/train",
            ),
            ProcessingOutput(
                output_name="validation",
                source="/opt/ml/processing/validation",
            ),
        ],
        code="preprocess.py",
    )

    # TRAINING step
    estimator = Estimator(
        image_uri=image_uri,
        instance_type=train_instance_type,
        instance_count=1,
        role=role_arn,
        hyperparameters={
            "n_estimators": n_estimators,
            "contamination": contamination,
            "random_state": 42,
            "max_samples": 256,
        },
        base_job_name="ai-sec-analyst-train",
    )

    step_train = TrainingStep(
        name="Train",
        estimator=estimator,
        inputs={
            "training": TrainingInput(
                s3_data=step_preprocess.properties.ProcessingOutputConfig.Outputs[
                    "train"
                ].S3Output.S3Uri,
                content_type="application/x-parquet",
            ),
        },
    )

    # EVALUATION step; scores model on held-out validation set
    evaluation_report = PropertyFile(
        name="EvaluationReport",
        output_name="evaluation",
        path="evaluation.json",
    )

    step_evaluate = ProcessingStep(
        name="Evaluate",
        processor=preprocessor,
        inputs=[
            ProcessingInput(
                source=step_train.properties.ModelArtifacts.S3ModelArtifacts,
                destination="/opt/ml/processing/model",
                input_name="model",
            ),
            ProcessingInput(
                source=step_preprocess.properties.ProcessingOutputConfig.Outputs[
                    "validation"
                ].S3Output.S3Uri,
                destination="/opt/ml/processing/validation",
                input_name="validation",
            ),
        ],
        outputs=[
            ProcessingOutput(
                output_name="evaluation",
                source="/opt/ml/processing/evaluation",
            ),
        ],
        code="evaluate.py",
        property_files=[evaluation_report],
    )

    # REGISTER step; PendingManualApproval gates promotion
    step_register = RegisterModel(
        name="RegisterModel",
        estimator=estimator,
        model_data=step_train.properties.ModelArtifacts.S3ModelArtifacts,
        content_types=["application/json"],
        response_types=["application/json"],
        inference_instances=["ml.t2.medium", "ml.m5.large"],
        transform_instances=["ml.m5.large"],
        model_package_group_name=model_package_group,
        approval_status="PendingManualApproval",
        model_metrics=ModelMetrics(
            model_statistics=MetricsSource(
                s3_uri=step_evaluate.properties.ProcessingOutputConfig.Outputs[
                    "evaluation"
                ].S3Output.S3Uri,
                content_type="application/json",
            )
        ),
    )

    # CONDITIONAL: only register if anomaly rate is sensible. Models that
    # find anomalies in 30%+ of validation data are likely broken.
    condition = ConditionLessThanOrEqualTo(
        left=JsonGet(
            step_name=step_evaluate.name,
            property_file=evaluation_report,
            json_path="anomaly_rate",
        ),
        right=max_anomaly_rate,
    )

    step_conditional_register = ConditionStep(
        name="CheckAnomalyRate",
        conditions=[condition],
        if_steps=[step_register],
        else_steps=[],
    )

    pipeline = Pipeline(
        name=f"{project.default_value}-anomaly-pipeline",
        parameters=[
            project, instance_type, train_instance_type,
            contamination, n_estimators, image_uri, role_arn,
            training_data_uri, model_package_group, max_anomaly_rate,
        ],
        steps=[step_preprocess, step_train, step_evaluate, step_conditional_register],
    )

    return json.loads(pipeline.definition())


if __name__ == "__main__":
    print(json.dumps(build_pipeline_definition(), indent=2))
