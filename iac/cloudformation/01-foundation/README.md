# 01-foundation (CloudFormation)

Parity equivalent of `iac/terraform/01-foundation/`.

## Important: do not deploy both IaC paths

CloudFormation and Terraform target the same AWS Organization/accounts/SCPs.
Deploying both will cause the second to fail. For this project, **Terraform
is the source of truth.** These templates are validated on every PR by the
`cfn-validate` workflow to prove parity.

If you want to deploy via CloudFormation instead of Terraform, comment out
the Terraform layer from the deploy workflow first.

## Stack order

CloudFormation has no native dependency resolution across separate stacks;
they must be deployed in this order because of `Fn::ImportValue`:

1. `org.yaml` → stack `ai-sec-analyst-01-foundation-org`
2. `accounts.yaml` → stack `ai-sec-analyst-01-foundation-accounts`
3. `scps.yaml` → stack `ai-sec-analyst-01-foundation-scps`

The `cfn-deploy` workflow deploys alphabetically within a layer, which
happens to be the correct order here (a, o, s).

## Parameters

`accounts.yaml` requires `RootEmail`. This is injected from the `ROOT_EMAIL`
GitHub secret by the `cfn-deploy` workflow.

## Deletion behavior

All `AWS::Organizations::Account` resources are tagged with
`DeletionPolicy: Retain` and `UpdateReplacePolicy: Retain`. CloudFormation
cannot actually delete an AWS account — the closest equivalent is removing
it from the stack and closing it manually. Retain policies prevent
CloudFormation from attempting account deletion on stack delete.
