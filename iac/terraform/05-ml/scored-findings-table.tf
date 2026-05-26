# Scored findings Glue table
#
# Schema mirrors the enriched_findings table from 04-data plus the four
# fields added by the inference Lambda. Partition projection on the same
# layout (source/year/month/day) as enriched_findings.
#
# Lives in this layer rather than 04-data because the schema explicitly
# depends on inference output contract.

resource "aws_glue_catalog_table" "scored_findings" {
  provider = aws.security_tooling

  database_name = data.terraform_remote_state.data.outputs.glue_database_name
  name          = "scored_findings"
  description   = "Inference-scored findings"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"                    = "TRUE"
    "classification"              = "json"
    "projection.enabled"          = "true"
    "projection.source.type"      = "enum"
    "projection.source.values"    = "guardduty,securityhub,custom"
    "projection.year.type"        = "integer"
    "projection.year.range"       = "2024,2030"
    "projection.month.type"       = "integer"
    "projection.month.range"      = "1,12"
    "projection.month.digits"     = "2"
    "projection.day.type"         = "integer"
    "projection.day.range"        = "1,31"
    "projection.day.digits"       = "2"
    "storage.location.template"   = "s3://${local.enriched_findings_bucket}/scored/$${source}/$${year}/$${month}/$${day}/"
  }

  partition_keys {
    name = "source"
    type = "string"
  }
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${local.enriched_findings_bucket}/scored/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    compressed    = false

    ser_de_info {
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    # Carry-over enriched fields
    columns {
      name = "finding_id"
      type = "string"
    }
    columns {
      name = "source"
      type = "string"
    }
    columns {
      name = "detail_type"
      type = "string"
    }
    columns {
      name = "severity"
      type = "string"
    }
    columns {
      name = "account_id"
      type = "string"
    }
    columns {
      name = "region"
      type = "string"
    }
    columns {
      name = "resource_arn"
      type = "string"
    }
    columns {
      name = "resource_tags"
      type = "map<string,string>"
    }
    columns {
      name = "raw_detail"
      type = "string"
    }
    columns {
      name = "enriched_at"
      type = "string"
    }

    # Inference Lambda additions
    columns {
      name = "anomaly_score"
      type = "double"
    }
    columns {
      name = "is_anomaly"
      type = "boolean"
    }
    columns {
      name = "scored_at"
      type = "string"
    }
    columns {
      name = "model_endpoint"
      type = "string"
    }
  }
}
