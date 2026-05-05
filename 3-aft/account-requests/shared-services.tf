# ============================================================
# Account Request — shared-services
# STATUS: CODE ONLY — DO NOT APPLY IN POC
#
# The shared-services account hosts infrastructure shared
# across all tenants:
#   - Amazon ECR (container image registry)
#   - Amazon Route 53 (DNS for all tenant domains)
#   - Amazon SES (email sending for all tenants)
#
# Tenants pull container images from ECR here rather than
# having their own registries — reduces duplication and cost.
# ============================================================

# module "shared_services" {
#   source = "github.com/aws-ia/terraform-aws-control_tower_account_factory//modules/aft-account-request"
#
#   control_tower_parameters = {
#     AccountName               = "shared-services"
#     AccountEmail              = var.shared_services_email
#     ManagedOrganizationalUnit = "Shared"
#     SSOUserEmail              = var.admin_email
#     SSOUserFirstName          = "Platform"
#     SSOUserLastName           = "Admin"
#   }
#
#   account_tags = {
#     managed_by   = "terraform"
#     account_type = "shared"
#     purpose      = "shared-platform-services"
#   }
#
#   custom_fields = {
#     account_type    = "shared"
#     workload_region = "ap-southeast-2"
#   }
#
#   account_customizations_name = "global"
# }
