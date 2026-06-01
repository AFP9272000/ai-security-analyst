# Part 2 outputs (agent + guardrail + tools)

output "agent_id" {
  value = aws_bedrockagent_agent.analyst.agent_id
}

output "agent_arn" {
  value = aws_bedrockagent_agent.analyst.agent_arn
}

output "agent_alias_id" {
  description = "Use with agent_id to invoke the agent via bedrock-agent-runtime"
  value       = aws_bedrockagent_agent_alias.live.agent_alias_id
}

output "agent_alias_arn" {
  value = aws_bedrockagent_agent_alias.live.agent_alias_arn
}

output "guardrail_id" {
  value = aws_bedrock_guardrail.analyst.guardrail_id
}

output "guardrail_arn" {
  value = aws_bedrock_guardrail.analyst.guardrail_arn
}

output "athena_tool_lambda_name" {
  value = aws_lambda_function.athena_tool.function_name
}

output "config_tool_lambda_name" {
  value = aws_lambda_function.config_tool.function_name
}
