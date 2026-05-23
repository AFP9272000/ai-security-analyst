# ADR 0005: Hybrid VPC Module Strategy

- **Status:** Accepted (Phase 2.0)
- **Context:** Phase 2 (Network) creates two VPCs - one in the Workload
  account, one in the Security Tooling account. The repeating
  "VPC + subnets + route tables + IGW" pattern is a natural module candidate

## Context

Three viable patterns for the VPC creation:

**A. Use `terraform-aws-modules/vpc/aws` directly.** The de-facto community
module, mature, ~30M downloads, exposes ~150 inputs that cover essentially
every variation seen in production VPCs.

**B. Write a custom module under `iac/terraform/modules/vpc/`.** Full
control over what variables are exposed, what resources are created,
naming conventions, opinionated defaults.

**C. Hybrid: a thin in-repo wrapper around the community module that
narrows the input surface to just what this project needs and documents
project-specific opinions.**

## Decision

**Adopted: C - hybrid wrapper.** `iac/terraform/modules/vpc/` calls
`terraform-aws-modules/vpc/aws` internally, exposing maybe 8-10 inputs
that match the patterns this project uses.

## Rationale

**Against pure A (community-direct):**

- The community module's 150-input surface area is hostile to readers. The
  `02-network` layer's `main.tf` would be 60 lines of `module "vpc"` block
  configuration with no opportunity to document why specific values were
  chosen.
- Anyone reviewing the project to evaluate Terraform skill would see only
  module-consumer code, not module-author code.

**Against pure B (fully custom):**

- Approximately 200-300 lines of TF to reimplement what the community
  module already does well, including subnet math, route table
  associations, IGW conditional logic, and subnet tagging for Kubernetes
  / load balancer auto-discovery.
- Real risk of bugs and edge cases the community module has already
  encountered and fixed.
- "Reinvented the wheel" is not a good portfolio story.

**For C (hybrid):**

- The wrapper is ~50-80 lines of TF: input variables, the community module
  call, outputs.
- Variables that the wrapper *does* expose are documented with
  project-specific rationale (e.g. "no NAT gateway by default - this
  project uses interface endpoints exclusively, see ADR-0002").
- The wrapper can encode project conventions: tag standard,
  `manage_default_security_group = false`, flow logs to the baseline
  CMK, opinionated subnet naming.
- For a reader, the relationship is clear: "this project depends on a
  well-known community module and adds project-specific opinions on top."
- For an interviewer, the question "what does your wrapper add over the
  raw community module?" has a clean answer.

## What the wrapper module exposes

| Input | Default | Purpose |
|---|---|---|
| `name` | required | VPC name; used for resource naming and tags |
| `cidr` | required | VPC CIDR block |
| `azs` | `["us-east-1a", "us-east-1b"]` | AZ list (matches our region constraint) |
| `public_subnet_cidrs` | `[]` | Empty disables IGW |
| `private_subnet_cidrs` | `[]` | App-tier subnets |
| `database_subnet_cidrs` | `[]` | DB-tier subnets, isolated |
| `enable_flow_logs` | `true` | Flow logs to CloudWatch with the baseline CMK |
| `tags` | `{}` | Merged with the project's tag standard |

Nothing else. NAT gateway support is explicitly NOT exposed because the
project's pattern uses interface endpoints instead. If a later project
need requires NAT, it goes through a deliberate module update with an
ADR addendum, not silent enablement.

## Consequences

**Positive:**

- The `02-network` layer is short and readable - two module calls plus
  endpoint configuration
- Module choices are documented in one place (the wrapper) rather than
  scattered across layer code
- Switching to a different upstream VPC module later is one place to
  change, not seven
- The wrapper is reusable if the project ever needs a third VPC

**Negative:**

- Indirection - readers have to look in two places (the layer and the
  wrapper) to fully understand the resources created
- The wrapper has to be versioned and tested alongside the community
  module - if upstream introduces a breaking change to inputs we use,
  the wrapper needs updating

**Mitigated:**

- The wrapper pins the upstream module version explicitly (no
  unconstrained `version = "~> 5.0"`)
- The wrapper has a `README.md` documenting which upstream inputs it
  exposes, hides, and overrides
- A unit test (in `tests/iac/`) deploys the wrapper to a sandbox account
  and verifies the resulting VPC structure - this also doubles as a
  smoke test when upgrading the upstream module version
