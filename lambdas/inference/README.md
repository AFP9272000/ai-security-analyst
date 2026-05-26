# Inference Lambda

Subscribes to enriched-findings S3 writes (via SQS), calls the SageMaker
anomaly detection endpoint, writes scored findings back to S3.

## Trigger chain

```
Enricher Lambda writes enriched/<source>/<date>/<id>.json
    -> S3 event notification (s3:ObjectCreated:*)
    -> SQS queue (ai-sec-analyst-inference-queue)
    -> Inference Lambda (this)
    -> writes scored/<source>/<date>/<id>.json to same bucket
```

S3 events are filtered to `enriched/` prefix only; the Lambda's own
writes to `scored/` are skipped at runtime to prevent loops (the
prefix filter usually handles this but the runtime check is defense-
in-depth).

## VPC mode

This Lambda runs **inside** the security-tooling private subnets
because the SageMaker endpoint is VPC-only (created in 05-ml Part 2
with `vpc_config`). Network path:

```
Lambda -> ENI in private subnet
       -> sagemaker.runtime VPC interface endpoint (Phase 2)
       -> SageMaker endpoint hosting model
```

If Phase 2 is torn down, this Lambda will fail to invoke (timeout).
That's by design - inference can't work without the endpoint, which
can't run without the VPC.

## Schema

Output adds three fields to the enriched finding:

| Field | Type | Source |
|---|---|---|
| `anomaly_score` | float | Endpoint `decision_function` output. Higher = more normal |
| `is_anomaly` | bool | Endpoint prediction (-1 mapped to true) |
| `scored_at` | string | UTC ISO 8601 timestamp |
| `model_endpoint` | string | Endpoint name for lineage |

All original enriched fields preserved.

## Local development

```powershell
# Run unit tests
cd $HOME\OneDrive\Desktop\aws-projects\ai-security-analyst
python -m pytest tests\unit\test_inference.py -v
```

## Partial batch failure

SQS triggers respect the `batchItemFailures` response. If 3 of 10
messages fail, only those 3 are returned to the queue for retry; the
7 successful ones are deleted normally. This avoids "one bad message
nukes the batch" reprocessing.

## Known limitations (v1)

- **Score is approximate.** The Lambda reconstructs a CloudTrail-like
  payload from the enriched finding, but it's a thin reconstruction.
  For better scoring, future versions could look up the actual
  CloudTrail event(s) via Athena and score the original event.
- **Model is shared across all finding sources.** GuardDuty, Security
  Hub, and custom findings all run through the same model. Specialized
  per-source models would likely improve precision.
- **No score-based routing.** The Lambda writes everything to S3. A
  future iteration could trigger high-severity actions (PagerDuty,
  Slack alert) when `is_anomaly && severity == "high"`.
