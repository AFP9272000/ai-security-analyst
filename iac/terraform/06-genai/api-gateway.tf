# API Gateway (HTTP API) - the chat front door (in Security Tooling)
#
# HTTP API (not REST) chosen for: native JWT authorizer (Cognito), lower
# cost, simpler config. The single route POST /chat is Cognito-authorized
# and proxies to the orchestrator Lambda. See ADR-0016.

resource "aws_apigatewayv2_api" "chat" {
  provider = aws.security_tooling

  name          = "${var.project}-chat-api"
  protocol_type = "HTTP"
  description   = "Security analyst chat API"

  cors_configuration {
    allow_origins = ["*"] # demo; tighten to your UI origin in production
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["content-type", "authorization"]
    max_age       = 300
  }
}

# Cognito JWT authorizer, validates ID tokens from the user pool
resource "aws_apigatewayv2_authorizer" "cognito" {
  provider = aws.security_tooling

  api_id           = aws_apigatewayv2_api.chat.id
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]
  name             = "${var.project}-cognito-jwt"

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.chat.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.chat.id}"
  }
}

# Lambda proxy integration
resource "aws_apigatewayv2_integration" "orchestrator" {
  provider = aws.security_tooling

  api_id                 = aws_apigatewayv2_api.chat.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.orchestrator.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
  timeout_milliseconds   = 30000 # API Gateway HTTP API hard max
}

# POST /chat, Cognito-authorized
resource "aws_apigatewayv2_route" "chat" {
  provider = aws.security_tooling

  api_id             = aws_apigatewayv2_api.chat.id
  route_key          = "POST /chat"
  target             = "integrations/${aws_apigatewayv2_integration.orchestrator.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

# Access logging
resource "aws_cloudwatch_log_group" "apigw" {
  provider          = aws.security_tooling
  name              = "/aws/apigateway/${var.project}-chat-api"
  retention_in_days = 30
  kms_key_id        = local.security_tooling_kms_arn
}

resource "aws_apigatewayv2_stage" "default" {
  provider = aws.security_tooling

  api_id      = aws_apigatewayv2_api.chat.id
  name        = "$default"
  auto_deploy = true

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.apigw.arn
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      requestTime    = "$context.requestTime"
      httpMethod     = "$context.httpMethod"
      routeKey       = "$context.routeKey"
      status         = "$context.status"
      responseLength = "$context.responseLength"
      integrationErr = "$context.integrationErrorMessage"
    })
  }
}

# Allow API Gateway to invoke the orchestrator
resource "aws_lambda_permission" "apigw_orchestrator" {
  provider = aws.security_tooling

  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.orchestrator.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.chat.execution_arn}/*/*"
}

# 30000ms note: the HTTP API integration cap is 30s. Agent answers
# (especially after an Aurora cold start) can approach this. The Lambda
# itself allows 120s and retries cold starts, but the API edge will
# return 504 if a single call exceeds 30s. Pre-warm before live demos
# (one throwaway question), or for production move to async (return a
# request id, poll/websocket for the answer). Noted in ADR-0016.
