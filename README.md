# AI Security Analyst - Conversational SOC Copilot on AWS

Multi-account AWS security platform with a generative-AI SOC copilot: centralized GuardDuty, Security Hub, and CloudTrail telemetry routed to a Bedrock agent over a pgvector knowledge base, ML anomaly scoring, event-driven auto-triage with alerting, and full observability. The complete detect-to-respond stack, built end to end as infrastructure as code.

![AWS](https://img.shields.io/badge/AWS-Bedrock%20%7C%20GuardDuty%20%7C%20Security%20Hub-FF9900)
![IaC](https://img.shields.io/badge/IaC-Terraform%20%2B%20CloudFormation-purple)
![CI/CD](https://img.shields.io/badge/CI%2FCD-GitHub%20Actions%20%2B%20CodePipeline-green)
![GenAI](https://img.shields.io/badge/GenAI-Bedrock%20Agent%20%7C%20pgvector%20KB%20%7C%20Guardrails-blueviolet)
![Auth](https://img.shields.io/badge/Auth-OIDC%20%7C%20Zero%20Secrets-brightgreen)
![Maps to](https://img.shields.io/badge/Maps%20to-SAP--C02%20%7C%20DOP--C02%20%7C%20MLA--C01%20%7C%20AIF--C01-orange)

## Overview

A production-grade security operations platform deployed across a four-account AWS Organization, pairing centralized threat detection with a generative-AI analyst that investigates findings in plain English and auto-triages the high-severity ones. Built with dual IaC implementations (Terraform + CloudFormation) and dual CI/CD pipelines (GitHub Actions + AWS CodePipeline), authenticated via GitHub OIDC with zero stored secrets.

**Key Metrics:**
- Centralizes findings across a **4-account AWS Organization** with SCP guardrails, KMS encryption, and least-privilege IAM
- Answers security questions **conversationally** via a Bedrock agent grounded in a pgvector knowledge base, with cited evidence and live data-lake queries
- **Auto-triages** high-severity GuardDuty and Security Hub findings in seconds: agent assessment plus SNS and Slack alert, fail-safe so the alert always sends
- Suppresses alert fatigue with **finding-level deduplication** across both detection sources
- Scores findings with a custom **SageMaker IsolationForest** pipeline gated by a model-registry approval
- Cuts vector-store idle cost by roughly **95%** versus OpenSearch Serverless via Aurora pgvector scale-to-zero
- Idles near **$40-50/month** through scale-to-zero and build-then-destroy patterns
- Dual IaC: identical platform deployable via **Terraform or CloudFormation**
- Documented with **23 ADRs** and a full **Well-Architected review**

## Architecture

<img width="1360" height="1010" alt="architectureai" src="https://github.com/user-attachments/assets/dcf305ab-90d1-4076-a1a0-16a5287708ab" />


## Security Controls

| Layer | Control | Implementation |
|-------|---------|---------------|
| **Organization** | Service Control Policies | Deny root, region restriction, deny-disable-security (destructive verbs only), deny-leave-org |
| **Encryption** | KMS customer-managed keys | CMKs across S3, DynamoDB, log groups, and the guardrail; AWS-managed keys where the service-principal burden is not warranted |
| **Access** | Least-privilege IAM | Per-function roles, PassRole constrained by PassedToService, confused-deputy guards (SourceAccount + SourceArn) |
| **Detection** | GuardDuty + Security Hub + CloudTrail | Delegated-admin aggregation across the organization |
| **AI guardrail** | Bedrock Guardrail | Credential and PII redaction, prompt-attack filtering, denied topic for offensive exploitation |
| **Tool safety** | Structured-parameter agent tools | Parameterized queries only, no free-form SQL from the model |
| **API** | Cognito + API Gateway | JWT authorizer, admin-create-only user pool |
| **Monitoring** | CloudWatch dashboard + alarms | Lambda errors, API 5xx, EventBridge delivery failures, routed to SNS |
| **Cost** | AWS Budgets + Cost Anomaly Detection | Threshold alerts and anomaly notifications by email |

## Detection to Response Pipeline

| Stage | Function | Implementation |
|-------|----------|---------------|
| **Detect** | Findings generated | GuardDuty, Security Hub, CloudTrail |
| **Route** | Event routing | EventBridge rules (severity-filtered) |
| **Normalize** | Canonical schema | Enricher Lambda to the S3 data lake |
| **Score** | Anomaly detection | SageMaker IsolationForest (off by default; seed data carries scores) |
| **Search** | Semantic retrieval | Bedrock Knowledge Base on Aurora pgvector |
| **Reason** | Investigation | Bedrock Agent (Claude Sonnet 4.5) with guardrail and tools |
| **Serve** | Analyst Q&A | Cognito to API Gateway to orchestrator Lambda |
| **Alert** | Auto-triage | EventBridge to triage Lambda to agent to SNS, deduplicated |

## Agent Tools

| Tool | Input | Function | Safety |
|------|-------|----------|--------|
| **query_security_findings** | severity, source, time window, anomaly flag | Structured query against the findings data lake (Athena) | Parameterized only, no free-form SQL, 15 unit tests |
| **get_resource_configuration** | resource id or ARN | Live resource state from AWS Config in the local account | Regex-validated inputs, read-only |

## Guardrail Controls

| Control | Type | Detection | Action |
|---------|------|-----------|--------|
| **Credential / PII redaction** | Sensitive information filter | AWS keys, passwords, email, phone, SSN, card numbers | Redact |
| **Prompt attack** | Content filter | Jailbreak and prompt-injection attempts | Block (HIGH) |
| **Violence / Misconduct** | Content filter | Graphic or illicit content | Flag (LOW, tuned to avoid blocking security terms) |
| **Offensive exploitation** | Denied topic | Requests to weaponize findings | Deny |

## Infrastructure as Code

This project demonstrates **dual IaC proficiency**, with the same platform deployable through either tool. Terraform is the deployed source of truth; CloudFormation is a maintained parity reference.

### Terraform

```
terraform/
├── 00-bootstrap/                    # Remote state backend (S3 + DynamoDB lock)
├── 00.5-codepipeline/               # CodePipeline CI/CD parity
├── 01-foundation/                   # Organization, OUs, SCPs, KMS, IAM baseline
├── 02-network/                      # Ephemeral VPC + interface endpoints (build then destroy)
├── 03-telemetry/                    # CloudTrail org trail, GuardDuty, Security Hub
├── 04-data/                         # S3 lake, Glue, Athena, enricher Lambda
├── 05-ml/                           # SageMaker pipeline, model registry, inference
├── 06-genai/                        # Bedrock KB (Aurora pgvector), guardrail, agent, chat API
├── 07-integration/                  # EventBridge alerting, auto-triage, dedup
└── 08-observability/                # CloudWatch dashboard, alarms, budgets, anomaly detection
```

**Backend:** Remote state in S3 (us-east-2) with a DynamoDB lock table, deliberately separate from the resource region (us-east-1)

**Pattern:** Each layer reads upstream outputs via remote state; every layer is independently plan/apply-able

### CloudFormation

```
cloudformation/
├── 01-foundation/                   # Org baseline parity
├── 03-telemetry/                    # Detection services parity
├── 04-data/                         # Data lake + enricher parity
├── 06-genai/                        # KB + agent + chat API parity
├── 07-integration/                  # Alerting + auto-triage parity
└── 08-observability/                # Dashboard + alarms + budget parity
```

**Parity:** Reproduces the deployed Terraform; Lambda code referenced from S3 artifacts, generated IDs passed as parameters

## CI/CD Pipelines

### GitHub Actions (`.github/workflows/terraform-deploy.yml`)

| Stage | Actions | Gate |
|-------|---------|------|
| **Authenticate** | GitHub OIDC to an AWS IAM role, backend init | Federated, zero secrets |
| **Plan** | `terraform plan` for the selected layer | Manual dispatch, choose layer |
| **Apply / Destroy** | Apply or destroy the selected layer | Explicit action input |

**Authentication:** GitHub OIDC to AWS IAM (zero stored secrets). Layer-selectable, so any of the ten layers can be planned, applied, or destroyed independently.

### AWS CodePipeline (`00.5-codepipeline`)

| Stage | Actions | Gate |
|-------|---------|------|
| **Source** | Repository source | - |
| **Build** | CodeBuild runs `terraform plan` | - |
| **Approve** | Manual approval action | Required before apply |
| **Deploy** | CodeBuild runs `terraform apply` | Post-approval |

**Authentication:** CodePipeline and CodeBuild service roles (zero static credentials)

## Observability

### Platform Dashboard (`ai-sec-analyst-platform`)

| Widget | Shows |
|--------|-------|
| **Lambda invocations / errors / duration** | All seven functions (enricher, inference, orchestrator, triage, provisioner, tools) |
| **Chat API** | Request count, 4xx, 5xx, p50 and p99 latency |
| **Alerting rule firings** | GuardDuty and Security Hub EventBridge invocations and failures |
| **DynamoDB** | Conversation-history read/write capacity and throttles |

### Alarms

| Alarm | Trigger | Action |
|-------|---------|--------|
| **Lambda errors** | Errors >= 1 on a critical function (5 min) | SNS alert topic |
| **Chat API 5xx** | 5xx >= 1 (5 min) | SNS alert topic |
| **Rule delivery failures** | EventBridge FailedInvocations >= 1 | SNS alert topic |

## Certification Alignment

| Domain | Certification | Demonstrated by |
|--------|---------------|-----------------|
| Multi-account org, SCPs, advanced networking, large-scale design | **SAP-C02** | foundation, network, telemetry layers |
| IaC, dual CI/CD, monitoring, automation | **DOP-C02** | dual IaC, GitHub Actions + CodePipeline, observability |
| ML pipeline, training, model registry, deployment | **MLA-C01** | SageMaker pipeline and inference layer |
| Generative AI, Bedrock, retrieval-augmented generation, prompt safety | **AIF-C01** | knowledge base, agent, guardrail |

## Quick Start

### Prerequisites
- AWS Organization with four accounts (management, log-archive, security-tooling, workload)
- A GitHub OIDC role in the management account
- Bedrock model access for an entitled Claude model (this build uses Claude Sonnet 4.5)
- Terraform >= 1.7.0
- AWS CLI installed

### Deploy with Terraform (via GitHub Actions)

```bash
# Clone repository
git clone https://github.com/AFP9272000/ai-security-analyst.git
cd ai-security-analyst

# Bootstrap the remote state backend (one-time)
#   Actions -> terraform-deploy -> layer: 00-bootstrap, action: apply

# Deploy the remaining layers in order, each via the workflow:
#   Actions -> terraform-deploy -> layer: 01-foundation ... 08-observability, action: plan, then apply
```

Local plans require initializing the remote backend first (the workflow handles this). Fetch resource IDs with the AWS CLI rather than `terraform output`.

### Deploy with CloudFormation

```bash
# Per layer, against the appropriate account and region
aws cloudformation deploy \
  --template-file iac/cloudformation/07-integration/alerting.yaml \
  --stack-name ai-sec-analyst-integration \
  --parameter-overrides AlertEmail=you@example.com AgentId=<id> ChatApiId=<id> \
  --capabilities CAPABILITY_NAMED_IAM \
  --region us-east-1
```

## Cost Management

| Resource | Cost | Optimization |
|----------|------|--------------|
| KMS customer-managed keys | ~$1 / key / month | Shared baseline keys per account |
| Aurora Serverless v2 (knowledge base) | ~$0 paused | Scale-to-zero, auto-pause after 1h idle |
| VPC interface endpoints (network layer) | ~$0.01 / hr each | Build then destroy; up only when needed |
| SageMaker inference endpoint | ~$50 / month if running | Off by default; agent uses seed scores |
| DynamoDB, S3, Secrets Manager | pennies / month | On-demand billing |
| Bedrock (Claude Sonnet 4.5) | cents per conversation | Pay per token |

**Idle footprint: roughly $20/month**, dominated by KMS keys.

```bash
# Tear down the ephemeral network layer when not in use
#   Actions -> terraform-deploy -> layer: 02-network, action: destroy

# Confirm the SageMaker inference endpoint is off (should list no in-service endpoints)
aws sagemaker list-endpoints --region us-east-1 \
  --query "Endpoints[?contains(EndpointName,'ai-sec-analyst')].[EndpointName,EndpointStatus]" --output table

# Aurora auto-pauses; confirm the capacity floor
aws rds describe-db-clusters --region us-east-1 \
  --query "DBClusters[?contains(DBClusterIdentifier,'ai-sec-analyst')].ServerlessV2ScalingConfiguration"
```

## Project Structure

```
ai-security-analyst/
├── iac/
│   ├── terraform/                   # 00-bootstrap ... 08-observability (source of truth)
│   └── cloudformation/              # parity templates
├── lambdas/
│   ├── enricher/                    # normalize findings to canonical schema
│   ├── inference/                   # anomaly scoring (SageMaker-backed)
│   ├── orchestrator/                # chat API to agent
│   ├── triage/                      # event-driven auto-triage + alert
│   ├── kb-provisioner/              # Aurora pgvector schema bootstrap
│   └── agent-tools/                 # athena_query, config_state
├── scripts/                         # seed, ask_agent, chat_client, simulate_attack, preflight_check
├── tests/unit/
├── docs/
│   ├── adr/                         # 23 architecture decision records
│   ├── architecture.drawio          # editable diagram source
│   ├── architecture.png             # exported diagram (referenced above)
│   ├── well-architected-review.md
│   └── demo-runbook.md
└── .github/workflows/               # terraform-deploy, codepipeline
```

## Skills Demonstrated

| Category | Technologies |
|----------|-------------|
| **AWS Organization & Security** | Organizations, SCPs, KMS, IAM, IAM Identity Center, GuardDuty, Security Hub, CloudTrail |
| **Generative AI** | Amazon Bedrock Agent, Knowledge Bases, Guardrails, Aurora PostgreSQL Serverless v2 + pgvector |
| **Machine Learning** | SageMaker pipelines, IsolationForest anomaly detection, Model Registry with approval gate |
| **Data** | S3 data lake, Glue Data Catalog, Athena, partition projection |
| **IaC** | Terraform (layered, remote state) + CloudFormation (parity) |
| **CI/CD** | GitHub Actions (OIDC) + AWS CodePipeline |
| **Serverless** | Lambda, API Gateway (HTTP API), EventBridge, SNS, DynamoDB, Cognito |
| **Observability** | CloudWatch dashboards and alarms, AWS Budgets, Cost Anomaly Detection |
| **Languages** | Python, HCL, YAML, Bash, PowerShell |

## Related Projects

- [Azure Hub-Spoke Network](https://github.com/AFP9272000/azure-hub-spoke-network): Enterprise hub-spoke topology with Azure Firewall, Front Door + WAF, and flow-log analytics
- [Azure Security Dashboard](https://github.com/AFP9272000/azure-security-dashboard): AKS-based SOC platform with Defender for Cloud integration
- [Azure Sentinel SIEM](https://github.com/AFP9272000/azure-sentinel-siem): 11 custom KQL analytics rules with MITRE ATT&CK mapping and Logic Apps playbooks
- [CloudTrail Security Monitor](https://github.com/AFP9272000/cloudtrail-security-monitor): AWS real-time security monitoring with Lambda, Security Hub, and EventBridge
- [Security Event Aggregator](https://github.com/AFP9272000/security-event-aggregator): Containerized microservices on ECS Fargate with MITRE ATT&CK mappings

## License

MIT License - see [LICENSE](LICENSE) for details.

---

**Addison Pirlo** | [LinkedIn](www.linkedin.com/in/addison-p-6406b225b) | [Email](mailto:addisonpirlo2@gmail.com)
