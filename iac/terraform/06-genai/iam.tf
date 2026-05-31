# Bedrock Knowledge Base service role (in Security Tooling)
#
# Assumed by bedrock.amazonaws.com. The KB uses it to:
#   - call the embedding model (Titan Text Embeddings V2)
#   - read source findings from the enriched bucket (S3)
#   - VALIDATE + read/write the Aurora cluster (DescribeDBClusters at
#     create time, then Data API for vectors)
#   - decrypt the DB secret + KMS-encrypted S3 objects
#
# The trust policy is scoped with aws:SourceAccount and an ArnLike on the
# KB ARN to prevent the confused-deputy problem.

data "aws_iam_policy_document" "kb_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.security_tooling_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${var.region}:${local.security_tooling_id}:knowledge-base/*"]
    }
  }
}

resource "aws_iam_role" "knowledge_base" {
  provider = aws.security_tooling

  name               = "${var.project}-knowledge-base"
  assume_role_policy = data.aws_iam_policy_document.kb_assume.json
  description        = "Service role for the Bedrock Knowledge Base"
}

data "aws_iam_policy_document" "knowledge_base" {
  # Invoke the embedding model
  statement {
    sid    = "InvokeEmbeddingModel"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
    ]
    resources = [
      "arn:aws:bedrock:${var.region}::foundation-model/${var.embedding_model_id}",
    ]
  }

  # Read source findings for ingestion
  statement {
    sid    = "ReadEnrichedBucket"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      local.enriched_findings_bucket_arn,
      "${local.enriched_findings_bucket_arn}/*",
    ]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceAccount"
      values   = [local.security_tooling_id]
    }
  }

  # Validate the Aurora cluster at KB-create time. Bedrock calls
  # DescribeDBClusters to confirm the cluster exists, is available, and
  # has the Data API (HTTP endpoint) enabled. This is the documented
  # required permission for a Bedrock KB on Aurora.
  statement {
    sid    = "RDSDescribeCluster"
    effect = "Allow"
    actions = [
      "rds:DescribeDBClusters",
    ]
    resources = [aws_rds_cluster.kb.arn]
  }

  # Read/write vectors via the Data API
  statement {
    sid    = "RDSDataAPI"
    effect = "Allow"
    actions = [
      "rds-data:ExecuteStatement",
      "rds-data:BatchExecuteStatement",
    ]
    resources = [aws_rds_cluster.kb.arn]
  }

  # DB credentials
  statement {
    sid    = "ReadDBSecret"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
    ]
    resources = [aws_rds_cluster.kb.master_user_secret[0].secret_arn]
  }

  # KMS for the secret and the encrypted S3 objects (same baseline CMK)
  statement {
    sid    = "KMSAccess"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
    resources = [local.security_tooling_kms_arn]
  }
}

resource "aws_iam_role_policy" "knowledge_base" {
  provider = aws.security_tooling

  role   = aws_iam_role.knowledge_base.id
  name   = "knowledge-base"
  policy = data.aws_iam_policy_document.knowledge_base.json
}
