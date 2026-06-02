# Part 3 outputs (API front door)

output "chat_api_endpoint" {
  description = "Base URL of the chat HTTP API"
  value       = aws_apigatewayv2_api.chat.api_endpoint
}

output "chat_api_url" {
  description = "Full POST URL for the chat route"
  value       = "${aws_apigatewayv2_api.chat.api_endpoint}/chat"
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.chat.id
}

output "cognito_app_client_id" {
  value = aws_cognito_user_pool_client.chat.id
}

output "conversation_table_name" {
  value = aws_dynamodb_table.conversations.name
}

output "orchestrator_lambda_name" {
  value = aws_lambda_function.orchestrator.function_name
}
