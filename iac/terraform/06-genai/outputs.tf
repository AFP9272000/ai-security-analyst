# Aurora vector store

output "aurora_cluster_arn" {
  value = aws_rds_cluster.kb.arn
}

output "aurora_cluster_endpoint" {
  value = aws_rds_cluster.kb.endpoint
}

output "aurora_secret_arn" {
  description = "RDS-managed master-password secret ARN (used by Bedrock + provisioner)"
  value       = aws_rds_cluster.kb.master_user_secret[0].secret_arn
}

output "kb_database_name" {
  value = var.kb_database_name
}

output "kb_vector_table" {
  value = local.kb_qualified_table
}

# Knowledge Base (consumed by Part 2 agent)

output "knowledge_base_id" {
  value = aws_bedrockagent_knowledge_base.security.id
}

output "knowledge_base_arn" {
  value = aws_bedrockagent_knowledge_base.security.arn
}

output "enriched_data_source_id" {
  description = "Trigger an ingestion job (sync) on this after seeding enriched/ findings"
  value       = aws_bedrockagent_data_source.enriched.data_source_id
}

output "scored_data_source_id" {
  description = "Trigger an ingestion job (sync) on this after seeding scored/ findings"
  value       = aws_bedrockagent_data_source.scored.data_source_id
}

output "knowledge_base_role_arn" {
  value = aws_iam_role.knowledge_base.arn
}
