# Glue

output "glue_database_name" {
  value = aws_glue_catalog_database.security.name
}

output "cloudtrail_table_name" {
  value = aws_glue_catalog_table.cloudtrail.name
}

output "enriched_findings_table_name" {
  value = aws_glue_catalog_table.enriched_findings.name
}

# Athena

output "athena_workgroup_name" {
  value = aws_athena_workgroup.security.name
}

output "athena_results_bucket_name" {
  value = aws_s3_bucket.athena_results.id
}

output "athena_results_bucket_arn" {
  value = aws_s3_bucket.athena_results.arn
}

# Enriched findings

output "enriched_findings_bucket_name" {
  value = aws_s3_bucket.enriched_findings.id
}

output "enriched_findings_bucket_arn" {
  value = aws_s3_bucket.enriched_findings.arn
}
