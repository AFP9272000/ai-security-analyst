# ADR 0004: CodePipeline Layer Parameterization

- **Status:** Accepted (Phase 2.0)
- **Context:** Adding AWS CodePipeline as a second CI/CD path required deciding
  how a single pipeline operates against multiple IaC layers

## Context

The GitHub Actions workflow `terraform-deploy.yml` accepts a `layer` input at
dispatch time (a dropdown listing `01-foundation`, `02-network`, etc.). The
chosen layer becomes an env var the workflow uses for the working directory
and the state key.

CodePipeline does not support input parameters at execution start in the
same way. `aws codepipeline start-pipeline-execution` accepts pipeline
variables, but they require the pipeline to declare them in its definition
and they can only be referenced in pipeline action configurations - not in
CodeBuild environment variables in a way that overrides defaults at start
time.

The result: a single `tf-deploy` CodePipeline cannot trivially "deploy
whichever layer the operator picks at start." Some path has to be chosen.

## Options considered

### Option A: Per-layer pipelines

Create `ai-sec-analyst-tf-deploy-02-network`,
`ai-sec-analyst-tf-deploy-03-telemetry`, etc. - one TF deploy pipeline and
one CFN deploy pipeline per IaC layer. For 7 layers that means 14 pipelines.

- **Pros:** layer is hardcoded in each pipeline. Approval scope is clear -
  approving the network pipeline cannot accidentally apply telemetry.
  Pipelines can be tightened to per-layer IAM (eventual). Matches the
  enterprise pattern where pipelines are slim and many.
- **Cons:** 14 pipeline resources in IaC. Roughly $14/month just in
  pipeline charges if all kept "active." Boilerplate-heavy Terraform.

### Option B: One pipeline, edit CodeBuild env var per use

Single `tf-deploy` pipeline. Operator edits the CodeBuild project's
`LAYER` environment variable in the console between executions.

- **Pros:** minimum IaC.
- **Cons:** ugly. The "approval gate" loses meaning - approver can't tell
  from the pipeline UI which layer is being applied unless they read the
  Build phase logs. Easy to forget to flip the var back. No audit trail
  in CloudTrail of what layer was deployed beyond CodeBuild's log group.

### Option C: One pipeline, side-channel CodeBuild execution

Single pipeline left at default `LAYER=01-foundation`. Operators wanting to
deploy other layers run the underlying CodeBuild project directly via
`aws codebuild start-build` with `--environment-variables-override`.

- **Pros:** the "main" pipeline path exercises the demoable flow against a
  meaningful layer. Layer overrides exist for power use without pipeline
  bloat.
- **Cons:** bypasses the approval gate entirely. Documented as a known
  limitation. The CodePipeline UI shows only the 01-foundation flow,
  understating capability to a reviewer.

### Option D: Pipeline variables with parameter store

Pipelines declare variables; pipeline action configurations reference them;
CodeBuild reads them via an SSM Parameter Store lookup in the buildspec.

- **Pros:** real parameterization at execution start.
- **Cons:** adds Parameter Store as a dependency. Requires writing the
  variable to SSM right before pipeline start (operator runs
  `aws ssm put-parameter` then `aws codepipeline start-pipeline-execution`).
  In practice the operator already has to assemble two commands - we may
  as well just run CodeBuild directly (Option C) and skip the approval gate.

## Decision

**Adopted: Option C** for the initial CodePipeline drop. The README for the
00.5-codepipeline layer documents both:

- The default pipeline path (deploys 01-foundation through the approval gate)
- The `aws codebuild start-build` override pattern for other layers (no
  approval, intentional)

**Planned evolution: migrate toward Option A** once Phase 7 ships and we
have all 7 layers stable. At that point the IaC for per-layer pipelines can
be expressed as a single Terraform module with a `for_each` over the layer
list, keeping the IaC clean.

## Rationale

The honest reasoning:

- **The CI/CD layer's purpose is to demonstrate the pattern, not to operate
  at production scale.** Reviewers will inspect the IaC and the runbook -
  they need to see "yes, this works end-to-end through CodePipeline." They
  do not need to see 14 pipelines.
- **The approval gate is meaningful even at 01-foundation.** Approving a
  change to Organizations or SCPs is the highest-risk approval in the
  project. If the demoable flow approves *that*, it is convincing.
- **Layer iteration speed matters during development.** Most layer changes
  during Phase 2-7 will be made through GitHub Actions, which already
  parameterizes layer cleanly. CodePipeline exists for parity and the
  enterprise pattern story, not for daily work.
- **Option A's cost would be real** - $14/month in pipeline charges is
  not nothing for a tear-down-between-sessions project.

## Consequences

**Positive:**

- 4 pipelines instead of 14
- Approval gate works for the demoable layer
- Power-user override exists for other layers
- IaC stays reviewable

**Negative:**

- CodePipeline UI under-represents the system's actual scope
- Power-user override skips approval; this is recorded in CodeBuild logs
  but not surfaced in CodePipeline history
- Migration to Option A later is a known follow-up, not yet implemented

**Mitigated:**

- The 00.5-codepipeline README documents both invocation patterns explicitly
- Future ADR will revisit when the per-layer migration ships
