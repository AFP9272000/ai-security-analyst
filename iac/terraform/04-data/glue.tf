# Glue catalog (in Security Tooling)
#
# Database + CloudTrail table with partition projection. No crawler:
# CloudTrail's S3 layout is deterministic, so partitions are projected at
# query time rather than discovered by a scheduled crawler. See
# docs/adr/0009-partition-projection-vs-crawler.md.
#
# Table location points cross-account at the log-archive bucket. The
# bucket policy (set in 03-telemetry) and the log-archive KMS key
# policy (set in 01-foundation) grant security-tooling principals the
# necessary GetObject + Decrypt permissions.

resource "aws_glue_catalog_database" "security" {
  provider = aws.security_tooling

  name        = "${replace(var.project, "-", "_")}_security"
  description = "Security data lake: CloudTrail, GuardDuty findings, Security Hub findings"
}

# CloudTrail table (org-wide trail)
#
# Schema based on the canonical CloudTrail JSON format. Partitions:
#   account_id: from path AWSLogs/<orgID>/<accountID>/...
#   region: from path .../<region>/...
#   year, month, day: from path .../<YYYY>/<MM>/<DD>/...
#
# CloudTrail file format: gzip-compressed JSON with a "Records" array.
# Athena's openx-json-serde flattens this at query time.

resource "aws_glue_catalog_table" "cloudtrail" {
  provider = aws.security_tooling

  database_name = aws_glue_catalog_database.security.name
  name          = "cloudtrail"
  description   = "Org CloudTrail logs from log-archive bucket (partition projection)"

  table_type = "EXTERNAL_TABLE"

  parameters = {
    "EXTERNAL"                       = "TRUE"
    "classification"                 = "cloudtrail"
    "projection.enabled"             = "true"
    "projection.account_id.type"     = "injected"
    "projection.region.type"         = "enum"
    "projection.region.values"       = "us-east-1,us-east-2,us-west-1,us-west-2,eu-west-1"
    "projection.year.type"           = "integer"
    "projection.year.range"          = "2024,2030"
    "projection.month.type"          = "integer"
    "projection.month.range"         = "1,12"
    "projection.month.digits"        = "2"
    "projection.day.type"            = "integer"
    "projection.day.range"           = "1,31"
    "projection.day.digits"          = "2"
    "storage.location.template"      = "s3://${local.log_archive_bucket_name}/AWSLogs/${local.org_id}/$${account_id}/CloudTrail/$${region}/$${year}/$${month}/$${day}/"
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

    # Canonical CloudTrail event columns
    columns {
      name = "eventversion"
      type = "string"
    }
    columns {
      name = "useridentity"
      type = "struct<type:string,principalid:string,arn:string,accountid:string,invokedby:string,accesskeyid:string,username:string,sessioncontext:struct<attributes:struct<mfaauthenticated:string,creationdate:string>,sessionissuer:struct<type:string,principalid:string,arn:string,accountid:string,username:string>,webidfederationdata:map<string,string>>>"
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
      name = "requestid"
      type = "string"
    }
    columns {
      name = "eventid"
      type = "string"
    }
    columns {
      name = "resources"
      type = "array<struct<arn:string,accountid:string,type:string>>"
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
      name = "serviceeventdetails"
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
      name = "tlsdetails"
      type = "struct<tlsversion:string,ciphersuite:string,clientprovidedhostheader:string>"
    }
  }
}
