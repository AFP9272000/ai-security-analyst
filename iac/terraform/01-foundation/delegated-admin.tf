# Delegated administrators (backfill)
#
# Security Tooling account becomes the org-level admin for security
# services. Once registered, the admin account can configure org-wide
# policies and auto-enroll member accounts.
#
# Trusted access for each service was already enabled on the Org
# (org.tf, aws_service_access_principals). These resources add the
# next step: nominating the specific account that gets admin rights.
#
# These registrations are org-level governance; they belong in the
# foundation layer and persist across telemetry layer destroys. See
# the ADR-0006 (deferred) on delegated admin placement.

locals {
  security_tooling_account_id = aws_organizations_account.members["security-tooling"].id
}

# Generic AWS Organizations delegated admin (covers Config, plus others
# that use the generic mechanism: IAM Access Analyzer, Health, etc.)
resource "aws_organizations_delegated_administrator" "config" {
  account_id        = local.security_tooling_account_id
  service_principal = "config.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "config_multiaccountsetup" {
  account_id        = local.security_tooling_account_id
  service_principal = "config-multiaccountsetup.amazonaws.com"
}

# GuardDuty uses its own enable-organization-admin-account API, not
# the generic delegated-administrator API. The Terraform resource
# wraps that call.
resource "aws_guardduty_organization_admin_account" "this" {
  admin_account_id = local.security_tooling_account_id

  depends_on = [aws_organizations_organization.this]
}

# Security Hub uses its own admin-account API too.
resource "aws_securityhub_organization_admin_account" "this" {
  admin_account_id = local.security_tooling_account_id

  depends_on = [aws_organizations_organization.this]
}
