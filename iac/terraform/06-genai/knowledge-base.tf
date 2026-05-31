# Bedrock Knowledge Base (in Security Tooling)
#
# Vector knowledge base backed by the Aurora pgvector table, embedding
# with Titan Text Embeddings V2. Ingests findings from the enriched
# bucket.
#
# Ordering: the KB validates the vector table on creation, so it must
# come AFTER the provisioner has created the schema. Hence the
# depends_on the lambda invocation.

resource "aws_bedrockagent_knowledge_base" "security" {
  provider = aws.security_tooling

  name     = "${var.project}-security-kb"
  role_arn = aws_iam_role.knowledge_base.arn

  knowledge_base_configuration {
    type = "VECTOR"
    vector_knowledge_base_configuration {
      embedding_model_arn = "arn:aws:bedrock:${var.region}::foundation-model/${var.embedding_model_id}"
    }
  }

  storage_configuration {
    type = "RDS"
    rds_configuration {
      resource_arn           = aws_rds_cluster.kb.arn
      credentials_secret_arn = aws_rds_cluster.kb.master_user_secret[0].secret_arn
      database_name          = var.kb_database_name
      table_name             = local.kb_qualified_table

      field_mapping {
        primary_key_field = "id"
        vector_field      = "embedding"
        text_field        = "chunk"
        metadata_field    = "metadata"
      }
    }
  }

  depends_on = [
    aws_lambda_invocation.kb_provisioner,
    aws_iam_role_policy.knowledge_base,
  ]
}

# S3 data sources - the enriched/ and scored/ findings
#
# Bedrock S3 data sources accept a MAXIMUM OF ONE inclusion prefix each,
# so each prefix gets its own data source under the same KB:
#   - enriched/ : always populated by the enricher Lambda
#   - scored/   : populated by the inference Lambda when the endpoint is
#                 up, and by the seed generator. Adds anomaly_score /
#                 is_anomaly signal the agent can cite.
#
# There is mild content overlap (a scored finding is an enriched finding
# plus score fields). Acceptable for a demo; the real fix is the
# narrative-templating ingestion enhancement noted in the README.
#
# Chunking: FIXED_SIZE with a small max. Finding JSONs are small and
# mostly self-contained, so most become a single chunk.

resource "aws_bedrockagent_data_source" "enriched" {
  provider = aws.security_tooling

  knowledge_base_id = aws_bedrockagent_knowledge_base.security.id
  name              = "${var.project}-enriched-findings"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = local.enriched_findings_bucket_arn
      inclusion_prefixes = ["enriched/"]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 20
      }
    }
  }
}

resource "aws_bedrockagent_data_source" "scored" {
  provider = aws.security_tooling

  knowledge_base_id = aws_bedrockagent_knowledge_base.security.id
  name              = "${var.project}-scored-findings"

  data_source_configuration {
    type = "S3"
    s3_configuration {
      bucket_arn         = local.enriched_findings_bucket_arn
      inclusion_prefixes = ["scored/"]
    }
  }

  vector_ingestion_configuration {
    chunking_configuration {
      chunking_strategy = "FIXED_SIZE"
      fixed_size_chunking_configuration {
        max_tokens         = 300
        overlap_percentage = 20
      }
    }
  }
}
