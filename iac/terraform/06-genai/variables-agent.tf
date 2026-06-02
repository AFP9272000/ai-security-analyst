# Part 2 variables (agent + guardrail + tools)
# Merges with variables.tf from Part 1.

variable "agent_foundation_model" {
  description = <<-EOT
    Foundation model for the Bedrock Agent. Newer Claude models require a
    cross-Region INFERENCE PROFILE ID (the "us." prefix), not a bare
    foundation-model ID. Verify what is enabled in account with:

      aws bedrock list-inference-profiles \
        --query "inferenceProfileSummaries[?contains(inferenceProfileId,'claude')].inferenceProfileId" \
        --output table

    Then set this to one of the listed IDs. The default below is a common
    US cross-Region Claude Sonnet profile; change it if your account has a
    different/newer one enabled.
  EOT
  type        = string
  default     = "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
}

variable "agent_idle_session_ttl" {
  description = "Seconds the agent keeps a session alive between turns."
  type        = number
  default     = 600
}

variable "guardrail_blocked_input_message" {
  type    = string
  default = "This request can't be processed. If you're investigating a security finding, rephrase as an analysis question."
}

variable "guardrail_blocked_output_message" {
  type    = string
  default = "The response was withheld by the content guardrail."
}
