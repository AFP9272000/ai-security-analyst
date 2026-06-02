# Part 3 variables (API front door)

variable "orchestrator_agent_alias_id" {
  description = <<-EOT
    Agent alias the orchestrator invokes. Defaults to TSTALIASID (the
    working draft), which always reflects the latest prepared agent - the
    most reliable choice for a demo and the same version the Bedrock
    console Test panel uses.

    To serve a pinned, published version instead, set this to the `live`
    alias id (from the agent_alias_id output) AFTER confirming that alias
    points at a version with your current model. See ADR-0016.
  EOT
  type        = string
  default     = "TSTALIASID"
}
