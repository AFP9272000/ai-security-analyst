# Cognito - authentication for the chat API (in Security Tooling)
#
# A user pool + app client. The API Gateway JWT authorizer validates
# Cognito-issued ID tokens against this pool. Admin-create-only (no public
# sign-up) since this is an internal analyst tool.
#
# Auth flows: USER_PASSWORD_AUTH is enabled so a simple test client
# (scripts/chat_client.py) can authenticate without implementing SRP.
# Production note in ADR-0016: prefer SRP or the hosted UI and disable
# USER_PASSWORD_AUTH.

resource "aws_cognito_user_pool" "chat" {
  provider = aws.security_tooling

  name = "${var.project}-analysts"

  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  password_policy {
    minimum_length                   = 12
    require_uppercase                = true
    require_lowercase                = true
    require_numbers                  = true
    require_symbols                  = true
    temporary_password_validity_days = 7
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  # MFA optional for the demo; production should set "ON" with TOTP.
  mfa_configuration = "OFF"

  user_pool_add_ons {
    advanced_security_mode = "AUDIT"
  }
}

resource "aws_cognito_user_pool_client" "chat" {
  provider = aws.security_tooling

  name         = "${var.project}-chat-client"
  user_pool_id = aws_cognito_user_pool.chat.id

  # Public client (no secret) so the test script can authenticate directly.
  generate_secret = false

  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_ADMIN_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
  ]

  # Token lifetimes
  id_token_validity      = 60 # minutes
  access_token_validity  = 60 # minutes
  refresh_token_validity = 1  # day
  token_validity_units {
    id_token      = "minutes"
    access_token  = "minutes"
    refresh_token = "days"
  }

  prevent_user_existence_errors = "ENABLED"
}
