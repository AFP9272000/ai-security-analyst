variable "region" {
  type    = string
  default = "us-east-1"
}

variable "state_region" {
  type    = string
  default = "us-east-2"
}

variable "project" {
  type    = string
  default = "ai-sec-analyst"
}

# Aurora vector store

variable "aurora_engine_version" {
  description = "Aurora PostgreSQL engine version. Must support pgvector and Serverless v2 scale-to-zero (>= 16.3 or >= 15.7). Verify availability with: aws rds describe-db-engine-versions --engine aurora-postgresql --query 'DBEngineVersions[].EngineVersion'"
  type        = string
  default     = "16.6"
}

variable "aurora_min_capacity" {
  description = "Aurora Serverless v2 minimum ACUs. 0 enables scale-to-zero (near-$0 idle). Fallback to 0.5 (~$43/mo) if your provider/engine version errors on 0."
  type        = number
  default     = 0
}

variable "aurora_max_capacity" {
  description = "Aurora Serverless v2 maximum ACUs."
  type        = number
  default     = 4
}

variable "aurora_seconds_until_auto_pause" {
  description = "Idle seconds before Aurora scales to 0 ACUs. Min 300, max 86400."
  type        = number
  default     = 3600
}

variable "vector_dimensions" {
  description = "Embedding vector dimensions. Titan Text Embeddings V2 default = 1024."
  type        = number
  default     = 1024
}

# Knowledge Base

variable "embedding_model_id" {
  description = "Bedrock embedding model ID."
  type        = string
  default     = "amazon.titan-embed-text-v2:0"
}

variable "kb_database_name" {
  description = "Logical database inside the Aurora cluster used by the Knowledge Base."
  type        = string
  default     = "kb"
}

variable "kb_schema_name" {
  description = "Postgres schema holding the vector table."
  type        = string
  default     = "bedrock_kb"
}

variable "kb_table_name" {
  description = "Vector table name (without schema prefix)."
  type        = string
  default     = "findings"
}
