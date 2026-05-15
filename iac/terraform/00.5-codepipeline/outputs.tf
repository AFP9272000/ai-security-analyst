output "artifact_bucket_name" {
  value = aws_s3_bucket.artifacts.id
}

output "codepipeline_role_arn" {
  value = aws_iam_role.codepipeline.arn
}

output "codebuild_role_arn" {
  value = aws_iam_role.codebuild.arn
}

output "pipeline_names" {
  value = {
    tf_validate  = aws_codepipeline.tf_validate.name
    tf_deploy    = aws_codepipeline.tf_deploy.name
    cfn_validate = aws_codepipeline.cfn_validate.name
    cfn_deploy   = aws_codepipeline.cfn_deploy.name
  }
}

output "start_pipeline_commands" {
  description = "Copy-paste-ready commands to start the deploy pipelines with a layer override."
  value = {
    tf_deploy_help = "aws codepipeline start-pipeline-execution --name ${aws_codepipeline.tf_deploy.name} --variables name=LAYER,value=<LAYER>"
    cfn_deploy_help = "aws codepipeline start-pipeline-execution --name ${aws_codepipeline.cfn_deploy.name} --variables name=LAYER,value=<LAYER>"
    note = "LAYER override requires CodeBuild project env var override at execution time. See README for the working pattern using aws codebuild start-build directly when fine-grained layer control is needed."
  }
}
