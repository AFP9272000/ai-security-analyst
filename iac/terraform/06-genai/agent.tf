# Bedrock Agent (in Security Tooling)
#
# The orchestrator: foundation model + knowledge base + the two action
# groups (defined in athena-tool.tf / config-tool.tf) + the guardrail.
#
# Ordering note: the action groups reference this agent's id, and the
# alias must point at a version that already has them attached. We set
# prepare_agent = true (the provider re-prepares when associations
# change) and make the alias depend on both action groups + the KB
# association so it snapshots a fully-wired agent.

# Agent service role
data "aws_iam_policy_document" "agent_assume" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.security_tooling_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${var.region}:${local.security_tooling_id}:agent/*"]
    }
  }
}

resource "aws_iam_role" "agent" {
  provider           = aws.security_tooling
  name               = "${var.project}-agent"
  assume_role_policy = data.aws_iam_policy_document.agent_assume.json
  description        = "Service role for the security analyst Bedrock Agent"
}

data "aws_iam_policy_document" "agent" {
  # Invoke the foundation model. Cross-Region inference profiles route to
  # the FM in multiple Regions, so we allow InvokeModel on BOTH the
  # inference-profile resources (in-account) AND the anthropic foundation
  # models (any Region).
  statement {
    sid    = "InvokeFoundationModelViaProfile"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream",
    ]
    resources = [
      "arn:aws:bedrock:*::foundation-model/anthropic.*",
      "arn:aws:bedrock:${var.region}:${local.security_tooling_id}:inference-profile/*",
      "arn:aws:bedrock:*:${local.security_tooling_id}:inference-profile/*",
    ]
  }

  # Retrieve from the knowledge base (created in Part 1, same state)
  statement {
    sid    = "RetrieveFromKnowledgeBase"
    effect = "Allow"
    actions = [
      "bedrock:Retrieve",
    ]
    resources = [aws_bedrockagent_knowledge_base.security.arn]
  }

  # Apply the guardrail
  statement {
    sid    = "ApplyGuardrail"
    effect = "Allow"
    actions = [
      "bedrock:ApplyGuardrail",
    ]
    resources = [aws_bedrock_guardrail.analyst.guardrail_arn]
  }

  # Decrypt the guardrail config. The guardrail is encrypted with the
  # security-tooling baseline CMK (kms_key_arn on the guardrail resource).
  # Applying a CMK-encrypted guardrail requires the caller's role to be
  # able to decrypt the key; without this, Bedrock reports the generic
  # "guardrail is invalid" error. The baseline key policy already allows
  # account principals via account-root kms:*, so this IAM grant is the
  # only missing piece.
  statement {
    sid    = "DecryptGuardrailKey"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = [local.security_tooling_kms_arn]
  }
}

resource "aws_iam_role_policy" "agent" {
  provider = aws.security_tooling
  role     = aws_iam_role.agent.id
  name     = "agent"
  policy   = data.aws_iam_policy_document.agent.json
}

# The agent
resource "aws_bedrockagent_agent" "analyst" {
  provider = aws.security_tooling

  agent_name                  = "${var.project}-analyst"
  agent_resource_role_arn     = aws_iam_role.agent.arn
  foundation_model            = var.agent_foundation_model
  idle_session_ttl_in_seconds = var.agent_idle_session_ttl
  prepare_agent               = true

  instruction = <<-EOT
    You are a cloud security analyst assistant for an AWS environment. You
    help security engineers understand findings, investigate incidents, and
    assess security posture.

    Capabilities available to you:
    - A knowledge base of enriched, anomaly-scored security findings from
      GuardDuty and Security Hub. Use it to answer what findings exist,
      their severity, affected resources, and anomaly scores. Always ground
      claims about findings in retrieved content and cite finding IDs.
    - query_security_findings: run precise structured queries against the
      findings data lake (filter by severity, source, time window, anomaly
      status). Prefer this over the knowledge base when the question asks
      for counts, filtered lists, trends, or "highest risk" rankings, where
      precision matters.
    - get_resource_configuration: look up the current AWS Config-recorded
      configuration of a resource by ID or ARN, to ground an answer in the
      resource's live state.

    Guidelines:
    - Ground every factual claim about findings in the knowledge base or a
      tool result. If you lack the data, say so plainly rather than guess.
    - Be concise and specific. Lead with the direct answer, then supporting
      detail. Cite finding IDs and resource ARNs so the analyst can follow up.
    - You analyze, explain, and help remediate security findings. You do NOT
      provide functional exploit code or step-by-step instructions to carry
      out attacks.
  EOT

  guardrail_configuration {
    guardrail_identifier = aws_bedrock_guardrail.analyst.guardrail_id
    guardrail_version    = aws_bedrock_guardrail.analyst.version
  }
}

# Knowledge base association
resource "aws_bedrockagent_agent_knowledge_base_association" "analyst" {
  provider = aws.security_tooling

  agent_id             = aws_bedrockagent_agent.analyst.agent_id
  knowledge_base_id    = aws_bedrockagent_knowledge_base.security.id
  knowledge_base_state = "ENABLED"
  description          = "Enriched and anomaly-scored security findings. Query this for what findings exist, their severity, affected resources, and anomaly scores."
}

# Alias (the invocable, versioned pointer)
resource "aws_bedrockagent_agent_alias" "live" {
  provider = aws.security_tooling

  agent_alias_name = "live"
  agent_id         = aws_bedrockagent_agent.analyst.agent_id
  description      = "Live alias for the security analyst agent"

  depends_on = [
    aws_bedrockagent_agent_knowledge_base_association.analyst,
    aws_bedrockagent_agent_action_group.athena_tool,
    aws_bedrockagent_agent_action_group.config_tool,
  ]
}
