# Bedrock Guardrail (in Security Tooling)
#
# Tuned specifically for a SECURITY ANALYST assistant. Two design points
# worth noting (see ADR-0014):
#
# 1. PII: we redact CREDENTIALS and PERSONAL identifiers (access keys,
#    secret keys, email, phone, name, password, SSN, card numbers) but
#    deliberately DO NOT redact IP addresses, ARNs, or account IDs,
#    those are the security-relevant evidence the analyst needs. A
#    generic Guardrail that anonymizes IPs would make this tool useless.
#
# 2. Content filters: PROMPT_ATTACK on input is set HIGH (jailbreak /
#    injection defense). Violence/misconduct filters are kept LOW, not
#    HIGH, because a security analyst legitimately discusses attack
#    techniques ("SSHBruteForce", "privilege escalation", "exfiltration")
#    and over-aggressive filters would block normal operation.

resource "aws_bedrock_guardrail" "analyst" {
  provider = aws.security_tooling

  name                      = "${var.project}-analyst-guardrail"
  description               = "Guardrail for the security analyst agent: credential/PII redaction, prompt-injection defense"
  blocked_input_messaging   = var.guardrail_blocked_input_message
  blocked_outputs_messaging  = var.guardrail_blocked_output_message
  kms_key_arn               = local.security_tooling_kms_arn

  # Prompt-injection / jailbreak defense on input
  content_policy_config {
    filters_config {
      type            = "PROMPT_ATTACK"
      input_strength  = "HIGH"
      output_strength = "NONE" # PROMPT_ATTACK only supports NONE on output
    }
    # Keep these LOW so legitimate security terminology isn't blocked.
    filters_config {
      type            = "VIOLENCE"
      input_strength  = "LOW"
      output_strength = "LOW"
    }
    filters_config {
      type            = "MISCONDUCT"
      input_strength  = "LOW"
      output_strength = "LOW"
    }
  }

  # Deny actually weaponizing the tool
  topic_policy_config {
    topics_config {
      name       = "OffensiveExploitation"
      type       = "DENY"
      definition = "Requests to generate functional exploit code, malware, or step-by-step instructions to actively carry out an attack against systems, as opposed to analyzing, explaining, or remediating findings."
      examples = [
        "Write a working exploit for this CVE so I can run it.",
        "Generate a script to brute-force these SSH credentials.",
        "Give me malware I can deploy to that instance.",
      ]
    }
  }

  # PII: redact credentials + personal identifiers
  # (IP addresses, ARNs, account IDs intentionally NOT listed.)
  sensitive_information_policy_config {
    pii_entities_config {
      type   = "AWS_ACCESS_KEY"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "AWS_SECRET_KEY"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PASSWORD"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "EMAIL"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "PHONE"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "NAME"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "US_SOCIAL_SECURITY_NUMBER"
      action = "ANONYMIZE"
    }
    pii_entities_config {
      type   = "CREDIT_DEBIT_CARD_NUMBER"
      action = "ANONYMIZE"
    }
  }
}
