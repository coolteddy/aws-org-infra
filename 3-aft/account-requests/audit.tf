# ============================================================
# Account Request — audit
# STATUS: CODE ONLY — DO NOT APPLY IN POC
#
# The audit account is the second mandatory Control Tower account.
# It runs security tooling that monitors all other accounts:
#   - AWS GuardDuty (threat detection aggregator)
#   - AWS Security Hub (compliance aggregator)
#   - AWS Config (configuration change aggregator)
#
# All member accounts send their findings here centrally.
# ============================================================

# module "audit" {
#   source = "github.com/aws-ia/terraform-aws-control_tower_account_factory//modules/aft-account-request"
#
#   control_tower_parameters = {
#     AccountName               = "audit"
#     AccountEmail              = var.audit_email
#     ManagedOrganizationalUnit = "Security"
#     SSOUserEmail              = var.admin_email
#     SSOUserFirstName          = "Platform"
#     SSOUserLastName           = "Admin"
#   }
#
#   account_tags = {
#     managed_by   = "terraform"
#     account_type = "security"
#     purpose      = "security-tooling-aggregator"
#   }
#
#   custom_fields = {
#     account_type = "security"
#   }
#
#   account_customizations_name = "global"
# }
