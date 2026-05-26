# ADR 0012: Inference Lambda Trigger and Network Placement

- **Status:** Accepted (Phase 5 Part 2)
- **Context:** The inference Lambda needs to consume enriched-finding
  events and call a SageMaker endpoint. Two independent architectural
  decisions: how it gets triggered, and where it runs in the network

## Context

The enricher Lambda (Phase 4) writes enriched JSON to S3 at
`s3://...-enriched-findings/enriched/<source>/<date>/<id>.json`. The
inference Lambda needs to:

1. Detect each new write
2. Read the finding from S3
3. Call the SageMaker endpoint (VPC-only)
4. Write a scored version back to S3

Two design questions:

**Q1: How to trigger the inference Lambda?**

- Option A: S3 event notification -> Lambda direct
- Option B: S3 event notification -> SQS -> Lambda
- Option C: EventBridge rule on the existing custom bus -> Lambda
- Option D: Lambda polls S3 on a schedule

**Q2: Should the Lambda run in-VPC or outside?**

- Option E: Outside VPC (faster cold starts, no Phase 2 dependency)
- Option F: Inside VPC (required for VPC-only SageMaker endpoint)

## Decisions

**Q1: Option B (S3 -> SQS -> Lambda).**

**Q2: Option F (in-VPC).**

## Rationale

### Q1: SQS between S3 and Lambda

**Visibility timeout handles slow endpoint responses.** SageMaker
endpoint inference latency is typically <100ms but can spike to several
seconds during cold starts. Direct S3->Lambda has no buffering; SQS
absorbs the burst and the visibility timeout (90s) prevents
duplicate processing during a slow invocation.

**Dead-letter queue.** SQS's redrive policy gives us a built-in DLQ
after 3 failed attempts. Poisoned events (malformed JSON, deleted
S3 objects, etc.) accumulate in the DLQ for offline inspection
rather than retrying forever.

**Partial batch failure semantics.** With `function_response_types =
["ReportBatchItemFailures"]`, the Lambda returns specific message IDs
that failed; only those are returned to the queue. Without SQS, S3
event notifications don't have this nuance.

**Decouples Lambda concurrency from S3 throughput.** If we ever get
a large batch of findings during an incident, SQS smooths the
delivery to whatever concurrency limit we configure (currently 10).

**Why not EventBridge (Option C)?** The custom bus is for routing
*findings* (logical security events), not file-write events. S3
notifications match the file-write semantics directly. Putting S3
events on EventBridge would conflate event types and add a
translation step that delivers no value.

**Why not polling (Option D)?** Wasteful at low volumes (mostly empty
polls), and we'd lose ordering guarantees that S3+SQS provides per-key.

### Q2: In-VPC for inference Lambda

This is the inverse of the enricher Lambda's outside-VPC decision
(ADR-0010). The reason: **the inference Lambda must reach the
SageMaker endpoint, and SageMaker endpoints in VPC mode are not
reachable from outside the VPC.**

The SageMaker endpoint runs in VPC mode (security-tooling private
subnets) because:
- Data plane should not traverse the public internet
- Model artifacts are sensitive (could be inferred-back from
  predictions in some threat models)
- Aligns with "everything sensitive lives behind the VPC" principle

Given that the endpoint is VPC-only, the Lambda must either:
- Run in the same VPC (Option F), or
- Run outside VPC and call the endpoint via... nothing. It can't.

So Option F is forced. The cost is the Phase 2 dependency.

## Consequences

**Positive:**

- Inference path has retry + DLQ + batch-failure semantics for free
- Endpoint traffic stays on the AWS backbone
- Inference Lambda concurrency is explicit and controllable
- DLQ inspection is a meaningful debugging surface

**Negative:**

- Inference Lambda fails when Phase 2 is torn down (no VPC, no ENI,
  no endpoint connectivity). This is by design - inference can't
  work without the endpoint anyway.
- VPC mode Lambdas have slower cold starts than non-VPC. For
  inference at ~100ms p50, cold start adds ~1-2 sec one-time per
  ENI allocation. Acceptable for a non-user-facing path.

**Mitigated:**

- The endpoint itself is variable-gated; teardown of Phase 2 implies
  teardown of the endpoint, so the Lambda's runtime dependency on
  the endpoint is correctly aligned
- ENI cold starts can be mitigated with Lambda SnapStart (future
  iteration) if latency ever matters

## Open questions for future iterations

- **Should the inference Lambda be VPC-aware about Phase 2 state?**
  Currently it will retry until DLQ if Phase 2 is down. A future
  version could detect endpoint absence and write the finding to a
  "pending-scoring" prefix for batch reprocessing when the endpoint
  returns. Not worth the complexity for v1.
