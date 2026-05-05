# ============================================================
# AFT — Account Factory for Terraform
# STATUS: CODE ONLY — DO NOT APPLY IN POC
#
# Reasons:
#   1. AFT requires Control Tower to be enrolled first
#   2. Costs ~$40-55/month when live (NAT Gateway runs 24/7)
#   3. Each vended account has a 90-day closure wait
#
# Apply this layer only when moving to production.
# ============================================================

terraform {
  backend "s3" {
    bucket         = "loadberry-org-tf-state-eu-west-2"
    key            = "aft/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "loadberry-org-tf-locks"
    encrypt        = true
  }
}
