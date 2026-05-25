# Glue catalog (in Security Tooling)
#
# Complex/nested columns (useridentity, tlsdetails, resources, etc.) are
# declared as `string` and parsed at query time with json_extract_scalar()
# - avoids HIVE_BAD_DATA errors from struct SerDe choking on missing
# nested fields.
#
# Example query:
#   SELECT eventtime, eventname,
#          json_extract_scalar(useridentity, '$.arn') AS user_arn
#   FROM ai_sec_analyst_security.cloudtrail
#   WHERE year = '2026' AND month = '05'
#   LIMIT 5;

resource "aws_glue_catalog_database" "security" {
  provider = aws.security_tooling

  name        = "${replace(var.project, "-", "_")}_security"
  description = "Security data lake: CloudTrail, GuardDuty findings, Security Hub findings"
}

resource "aws_glue_catalog_table" "cloudtrail" {
  provider = aws.security_tooling

  database_name = aws_glue_catalog_database.security.name
  name          = "cloudtrail"
  description   = "Org CloudTrail logs from log-archive bucket (partition projection)"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"                     = "TRUE"
    "classification"               = "cloudtrail"
    "projection.enabled"           = "true"
    "projection.account_id.type"   = "enum"
    "projection.account_id.values" = "${local.mgmt_account_id},${local.log_archive_account_id},${local.security_tooling_id},${local.workload_account_id}"
    "projection.region.type"       = "enum"
    "projection.region.values"     = "us-east-1,us-east-2,us-west-1,us-west-2,eu-west-1"
    "projection.year.type"         = "integer"
    "projection.year.range"        = "2024,2030"
    "projection.month.type"        = "integer"
    "projection.month.range"       = "1,12"
    "projection.month.digits"      = "2"
    "projection.day.type"          = "integer"
    "projection.day.range"         = "1,31"
    "projection.day.digits"        = "2"
    "storage.location.template"    = "s3://${local.log_archive_bucket_name}/AWSLogs/${local.org_id}/$${account_id}/CloudTrail/$${region}/$${year}/$${month}/$${day}/"
  }

  partition_keys {
    name = "account_id"
    type = "string"
  }
  partition_keys {
    name = "region"
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
    location      = "s3://${local.log_archive_bucket_name}/AWSLogs/${local.org_id}/"
    input_format  = "com.amazon.emr.cloudtrail.CloudTrailInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.HiveIgnoreKeyTextOutputFormat"
    compressed    = true

    ser_de_info {
      serialization_library = "com.amazon.emr.hive.serde.CloudTrailSerde"
    }

    # Scalar columns
    columns {
      name = "eventversion"
      type = "string"
    }
    columns {
      name = "eventtime"
      type = "string"
    }
    columns {
      name = "eventsource"
      type = "string"
    }
    columns {
      name = "eventname"
      type = "string"
    }
    columns {
      name = "awsregion"
      type = "string"
    }
    columns {
      name = "sourceipaddress"
      type = "string"
    }
    columns {
      name = "useragent"
      type = "string"
    }
    columns {
      name = "errorcode"
      type = "string"
    }
    columns {
      name = "errormessage"
      type = "string"
    }
    columns {
      name = "requestid"
      type = "string"
    }
    columns {
      name = "eventid"
      type = "string"
    }
    columns {
      name = "eventtype"
      type = "string"
    }
    columns {
      name = "apiversion"
      type = "string"
    }
    columns {
      name = "readonly"
      type = "string"
    }
    columns {
      name = "recipientaccountid"
      type = "string"
    }
    columns {
      name = "sharedeventid"
      type = "string"
    }
    columns {
      name = "vpcendpointid"
      type = "string"
    }
    columns {
      name = "managementevent"
      type = "string"
    }
    columns {
      name = "eventcategory"
      type = "string"
    }

    # Complex/nested columns - stored as JSON strings, queried with
    # json_extract_scalar(). Avoids HIVE_BAD_DATA on missing nested fields.
    columns {
      name = "useridentity"
      type = "string"
    }
    columns {
      name = "requestparameters"
      type = "string"
    }
    columns {
      name = "responseelements"
      type = "string"
    }
    columns {
      name = "additionaleventdata"
      type = "string"
    }
    columns {
      name = "resources"
      type = "string"
    }
    columns {
      name = "serviceeventdetails"
      type = "string"
    }
    columns {
      name = "tlsdetails"
      type = "string"
    }
  }
}
