# 01-foundation (Terraform)

Establishes the Organizational baseline: AWS Organization, OUs, member
accounts, Service Control Policies.

## What this layer creates

- **AWS Organization** with `ALL` feature set, SCPs and Tag Policies enabled
- **OUs**: `Security`, `Workload`
- **Member accounts**:
  - `ai-sec-analyst-log-archive` → Security OU
  - `ai-sec-analyst-security-tooling` → Security OU
  - `ai-sec-analyst-workload` → Workload OU
- **SCPs** attached to both OUs:
  - `deny-root` — block root user API calls
  - `deny-regions` — restrict to `us-east-1`, `us-east-2`
  - `deny-disable-security` — block disabling CloudTrail/GuardDuty/Config/Security Hub
  - `deny-leave-org` — block accounts from leaving the Organization
- **Trusted access** enabled for CloudTrail, Config, GuardDuty, Security Hub, SSO, RAM

## Prerequisites

1. `00-bootstrap` complete (state backend, OIDC, gha-bootstrap-role)
2. GitHub repo secret `ROOT_EMAIL` set to base Gmail address
3. GitHub repo secret `AWS_GHA_ROLE_ARN` set (done in Phase 1.0)
4. Management account is NOT already part of an Organization (fresh state)

## Deploy

Via GitHub Actions workflow dispatch (recommended):

1. Repo → Actions → **terraform-deploy** → Run workflow
2. Inputs: layer = `01-foundation`, action = `plan`
3. Review the plan output
4. Re-run with action = `apply`, approve at the `prod` environment gate

Local plan (smoke test, requires direct AWS creds):

```powershell
cd iac\terraform\01-foundation
cp terraform.tfvars.example terraform.tfvars   # edit with your email
terraform init `
  -backend-config=..\backend.hcl `
  -backend-config="key=01-foundation/terraform.tfstate"
terraform plan
```

## Destroy caveat

`terraform destroy` will detach SCPs and remove OUs. It will NOT delete the
member accounts — AWS Organizations imposes a 30-day cooldown after account
closure, and Terraform leaves accounts intact by default. To fully clean up:

1. `terraform destroy` removes SCPs/OUs and disassociates accounts from Terraform state
2. Manually close accounts in AWS Console (Billing → Close Account) — accounts enter SUSPENDED state for 90 days

For this portfolio project, **the recommendation is to NEVER destroy
01-foundation.** Accounts and the Org are foundational and effectively
persistent. Ephemeral teardown happens at layers 02 onward.

## Outputs consumed downstream

| Output | Consumer |
|---|---|
| `account_ids["log-archive"]` | 03-telemetry (S3 bucket policies) |
| `account_ids["security-tooling"]` | 03-telemetry, 04-data, 05-ml, 06-genai |
| `account_ids["workload"]` | 02-network, 07-workload |
| `organization_id` | 03-telemetry (CloudTrail org trail) |

Downstream layers reference these via `terraform_remote_state` data source.
