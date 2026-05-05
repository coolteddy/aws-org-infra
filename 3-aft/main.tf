# ============================================================
# AFT — Account Factory for Terraform
# STATUS: CODE ONLY — DO NOT APPLY IN POC
# ============================================================

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# ------------------------------------------------------------------------------
# AFT Module
#
# This single module call deploys the entire AFT pipeline infrastructure
# in the management account. Under the hood it creates:
#
#   Networking:
#     - VPC with public + private subnets
#     - NAT Gateway (~$32-45/month — runs 24/7 even when idle)
#       This is the primary ongoing cost of AFT.
#
#   Pipeline:
#     - AWS CodePipeline — detects commits to account-requests/
#     - AWS CodeBuild    — runs Terraform for each account request
#     - AWS Step Functions — orchestrates the vending workflow
#     - AWS Lambda       — handles Control Tower callbacks
#
#   Storage:
#     - S3 buckets       — pipeline artefacts and state
#     - DynamoDB tables  — AFT request tracking
#
#   Messaging:
#     - SQS queues       — async account request processing
#     - SNS topics       — notifications on completion
#
# Module source: https://github.com/aws-ia/terraform-aws-control_tower_account_factory
# ------------------------------------------------------------------------------

# module "aft" {
#   source = "github.com/aws-ia/terraform-aws-control_tower_account_factory"
#
#   # ---- Management account IDs ----
#   # Control Tower management account (where AFT pipeline runs)
#   ct_management_account_id = var.management_account_id
#
#   # AFT can run in the management account or a dedicated AFT account.
#   # Using the management account here for simplicity.
#   aft_management_account_id = var.management_account_id
#
#   # These accounts are created automatically when Control Tower is enrolled.
#   # Get their IDs from: AWS Organizations → Accounts
#   log_archive_account_id = var.log_archive_account_id
#   audit_account_id       = var.audit_account_id
#
#   # ---- Regions ----
#   # Must match the Control Tower home region set during CT enrollment.
#   ct_home_region = "eu-west-2"
#
#   # Secondary region for Terraform state replication (DR).
#   # Can be the same as home region for simplicity.
#   tf_backend_secondary_region = "eu-west-2"
#
#   # ---- GitHub integration ----
#   # AFT watches this repo for changes to account-requests/ directory.
#   # When a new .tf file is committed, CodePipeline triggers automatically.
#   vcs_provider                = "github"
#   account_request_repo_name   = "${var.github_org}/aws-org-infra"
#   account_request_repo_branch = "main"
#
#   # AFT also needs a repo for account customisations.
#   # This is the same repo — customisations live in account-customizations/
#   account_customizations_repo_name   = "${var.github_org}/aws-org-infra"
#   account_customizations_repo_branch = "main"
#
#   # ---- Terraform version ----
#   # AFT uses this version to run Terraform inside CodeBuild.
#   # Must match the version used in this repo.
#   terraform_version      = "1.6.0"
#   terraform_distribution = "oss"
#
#   # ---- Global customisations ----
#   # These run in EVERY vended account automatically.
#   # See account-customizations/global/ for the implementation.
#   global_customizations_repo_name   = "${var.github_org}/aws-org-infra"
#   global_customizations_repo_branch = "main"
# }
