# ------------------------------------------------------------------------------
# AWS Accounts
#
# One resource block = one AWS account.
# All account changes go through a PR - human approval required.
# See ACCOUNT.md for account purposes, naming and creation workflow.
#
# Importing an existing account (run locally, one-time):
#   terraform import aws_organizations_account.RESOURCE_NAME ACCOUNT_ID
#   terraform state rm aws_organizations_account.RESOURCE_NAME  (to untrack)
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Example: Importing and managing an existing account
#
# This block shows the pattern for bringing an existing AWS account under
# Terraform management. The actual import was done locally for this POC
# and the account is not tracked in this public repo's state.
#
# Steps used:
#   1. terraform import aws_organizations_account.shared_services ACCOUNT_ID
#   2. terraform apply  (renamed account + moved to Shared OU)
#   3. terraform state rm aws_organizations_account.shared_services
#      (removed from state so this public repo does not track personal accounts)
#
# To use this pattern for your own account:
#   1. Uncomment the block below
#   2. Replace values with your account details
#   3. Add the real email to terraform.tfvars (gitignored)
#   4. Run: terraform import aws_organizations_account.shared_services YOUR_ACCOUNT_ID
#   5. Run: terraform plan  (verify rename + OU move)
#   6. Run: terraform apply
# ------------------------------------------------------------------------------

# resource "aws_organizations_account" "shared_services" {
#   name      = "shared-services"
#   email     = var.shared_services_email
#   parent_id = aws_organizations_organizational_unit.shared.id
#
#   # AWS does not allow changing an account email via the API after creation.
#   # ignore_changes prevents Terraform from showing a permanent diff on this field.
#   # close_on_deletion = false means removing this block will NOT close the account.
#   close_on_deletion = false
#
#   lifecycle {
#     prevent_destroy = true
#     ignore_changes  = [email]
#   }
#
#   tags = {
#     account_type = "shared"
#     purpose      = "shared-platform-services"
#     managed_by   = "terraform"
#   }
# }

# ------------------------------------------------------------------------------
# sandbox
#
# Development and POC workload account.
# Planned workloads: EKS, ALB, NLB, Transit Gateway attachment, networking POC.
# ------------------------------------------------------------------------------

resource "aws_organizations_account" "sandbox" {
  name      = "sandbox"
  email     = var.sandbox_email
  parent_id = aws_organizations_organizational_unit.tenant_a.id

  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    account_type = "sandbox"
    purpose      = "eks-networking-poc"
    managed_by   = "terraform"
  }
}

# ------------------------------------------------------------------------------
# log-archive
#
# Immutable audit trail account in the Security OU.
# Receives CloudTrail logs and AWS Config snapshots from all org accounts.
# S3 bucket uses Object Lock — objects cannot be deleted before retention expires.
# ------------------------------------------------------------------------------

resource "aws_organizations_account" "log_archive" {
  name      = "log-archive"
  email     = var.log_archive_email
  parent_id = aws_organizations_organizational_unit.security.id

  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    account_type = "security"
    purpose      = "immutable-audit-trail"
    managed_by   = "terraform"
  }
}

# ------------------------------------------------------------------------------
# audit
#
# Security monitoring hub in the Security OU.
# GuardDuty and Security Hub delegated admin — aggregates findings from all accounts.
# Analysts work here, not in the log-archive account.
# ------------------------------------------------------------------------------

resource "aws_organizations_account" "audit" {
  name      = "audit"
  email     = var.audit_email
  parent_id = aws_organizations_organizational_unit.security.id

  close_on_deletion = false

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    account_type = "security"
    purpose      = "guardduty-securityhub-hub"
    managed_by   = "terraform"
  }
}
