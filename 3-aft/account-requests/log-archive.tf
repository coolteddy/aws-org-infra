# ============================================================
# Account Request — log-archive
# STATUS: CODE ONLY — DO NOT APPLY IN POC
#
# This file provisions the log-archive AWS account via AFT.
# log-archive is one of two mandatory accounts created by
# Control Tower. It stores immutable audit logs from all
# accounts (CloudTrail, Config, S3 access logs).
#
# In production: commit this file → CodePipeline triggers →
# Control Tower creates the account → AFT runs customisations.
# ============================================================

# module "log_archive" {
#   source = "github.com/aws-ia/terraform-aws-control_tower_account_factory//modules/aft-account-request"
#
#   # ---- Account identity ----
#   # The account name appears in the AWS Organizations console.
#   control_tower_parameters = {
#     AccountName            = "log-archive"
#     AccountEmail           = var.log_archive_email
#
#     # Which OU this account belongs to.
#     # Security OU is managed by Control Tower for audit accounts.
#     ManagedOrganizationalUnit = "Security"
#
#     # SSO user who gets initial admin access to this account.
#     SSOUserEmail     = var.admin_email
#     SSOUserFirstName = "Platform"
#     SSOUserLastName  = "Admin"
#   }
#
#   # ---- Account tags ----
#   # These tags are applied to the account in AWS Organizations.
#   # They flow through to billing and cost allocation reports.
#   account_tags = {
#     managed_by   = "terraform"
#     account_type = "security"
#     purpose      = "centralised-audit-logging"
#   }
#
#   # ---- Custom fields ----
#   # Key-value pairs passed to account customisation scripts.
#   # Use these to pass account-specific config to global customisations.
#   custom_fields = {
#     account_type = "security"
#   }
#
#   # ---- Customisations ----
#   # Which customisation scripts run after the account is created.
#   # "global" runs the scripts in account-customizations/global/
#   account_customizations_name = "global"
# }
