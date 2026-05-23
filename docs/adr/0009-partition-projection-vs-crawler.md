# ADR 0009: Partition Projection over Glue Crawler

- **Status:** Accepted 
- **Context:** The CloudTrail Glue table needed a partitioning strategy

## Context

CloudTrail org trail writes objects to S3 with a deterministic path:

```
s3://ai-sec-analyst-cloudtrail-logs-<acct>/AWSLogs/<orgID>/<accountID>/CloudTrail/<region>/<YYYY>/<MM>/<DD>/<gzipped_json>
```

For Athena queries to scan only the relevant subset, the Glue table
needs partitions registered for `account_id`, `region`, `year`,
`month`, and `day`.

Two ways to do that:

**Crawler.** AWS Glue runs a scheduled crawler that walks S3 prefixes
and registers each partition as a Glue partition metadata record.
Cost: $0.44 per crawl + cumulative cost over schedule. Operationally:
crawler can fall behind on high-cardinality partitions, and creates an
additional resource that needs IAM + scheduling.

**Partition projection.** Athena projects partitions at query time
based on metadata rules attached to the table. No physical partition
records, no crawler, no schedule. Athena resolves the projection
template to the S3 prefix it needs for a given query's partition
predicate, then reads only the matching objects.

## Decision

**Partition projection.** No crawler in the project.

## Rationale

- **Cost.** Crawler runs add real spend. A weekly crawler at $0.44/run
  is small per-run but non-zero and compounds with multiple tables.
  Partition projection cost: $0.
- **Correctness on a deterministic path.** Crawlers are valuable when
  the S3 layout is dynamic or unpredictable. CloudTrail's path is
  rigidly defined by AWS; projection is mathematically equivalent
  to a perfect crawl.
- **Less operational surface.** No crawler = no IAM role for the
  crawler, no schedule expression, no error path when the crawler
  fails or runs late.
- **Faster query startup.** Partition projection adds zero latency
  vs hundreds-of-partitions table metadata lookups when the table is
  highly partitioned.

## Consequences

**Positive:**

- ~$2-5/month saved across the data lake
- One less resource type in IaC
- Query latency unchanged or marginally better
- Schema changes don't require a re-crawl

**Negative:**

- Range/enum values for projected partitions are hardcoded in the
  table metadata. Extending the year range past 2030 or adding a new
  AWS region requires a Terraform apply. Acceptable trade-off given
  multi-year deploy cadence
- Partition projection requires Athena engine v2 or v3 (default since
  2021; no risk in fresh deploys)

**Mitigated:**

- Year range set to 2024-2030, six-year buffer
- Region projection covers us-east-1, us-east-2, us-west-1, us-west-2,
  eu-west-1; can be extended as needed via TF apply
