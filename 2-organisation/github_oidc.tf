# ------------------------------------------------------------------------------
# GitHub Actions OIDC — Keyless Authentication
#
# How it works:
#   GitHub generates a short-lived JWT token for each Actions job.
#   AWS verifies the token against this OIDC provider.
#   If the role's trust policy matches, AWS issues temporary credentials.
#   No static keys stored anywhere. Credentials expire after 1 hour max.
#
# This file owns ALL GitHub Actions IAM roles for the organisation.
# When a new Terraform repo is created, add its role here — not in that repo.
# This keeps all cross-account trust relationships in one auditable place.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# OIDC Provider — created once, shared by all repos
#
# The thumbprint is a hash of GitHub's TLS certificate used to verify
# GitHub's identity when AWS fetches their public signing keys.
# Note: AWS now trusts GitHub's CA bundle directly, so the thumbprint
# is largely symbolic — but Terraform requires the field to be present.
# ------------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]

  # GitHub's TLS certificate thumbprint.
  # AWS verifies this when fetching GitHub's public JWKS keys.
  # Thumbprint = SHA-1 of GitHub's OIDC server TLS root certificate.
  # Fetch the current value via: AWS Console → IAM → Identity providers
  # → token.actions.githubusercontent.com → Manage thumbprints → Get thumbprint
  # This value changes when GitHub rotates their TLS certificate.
  thumbprint_list = ["2b18947a6a9fc7764fd8b5fb18a863b0c6dac24f"]

  tags = var.tags
}

# ------------------------------------------------------------------------------
# IAM Role — aws-org-infra (this repo)
#
# Trust policy conditions explained:
#   aud = audience — must be sts.amazonaws.com (the AWS STS service)
#   sub = subject  — scoped to this specific GitHub repo
#         the wildcard (*) allows any branch or PR to assume this role
#         so terraform plan runs on PRs and terraform apply runs on main
#         Apply is protected by the GitHub Actions environment approval gate,
#         not by restricting the role itself.
# ------------------------------------------------------------------------------

resource "aws_iam_role" "github_aws_org_infra" {
  name        = "github-actions-aws-org-infra"
  description = "Assumed by GitHub Actions workflows in the aws-org-infra repo."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "GitHubOIDCTrust"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# AdministratorAccess — required because this role manages org-level resources:
# Organizations, SCPs, IAM Identity Center, IAM roles, Config rules.
resource "aws_iam_role_policy_attachment" "github_aws_org_infra_admin" {
  role       = aws_iam_role.github_aws_org_infra.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ------------------------------------------------------------------------------
# Template — add future repo roles below this block
#
# Pattern for each new Terraform repo:
#
# resource "aws_iam_role" "github_<repo_name>" {
#   name        = "github-actions-<repo-name>"
#   description = "Assumed by GitHub Actions in the <repo-name> repo."
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Sid    = "GitHubOIDCTrust"
#       Effect = "Allow"
#       Principal = {
#         Federated = aws_iam_openid_connect_provider.github.arn
#       }
#       Action = "sts:AssumeRoleWithWebIdentity"
#       Condition = {
#         StringEquals = {
#           "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
#         }
#         StringLike = {
#           # Restrict to main branch only for apply — tighter than the org role
#           "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/<repo-name>:ref:refs/heads/main"
#         }
#       }
#     }]
#   })
#
#   tags = var.tags
# }
#
# resource "aws_iam_role_policy_attachment" "github_<repo_name>_policy" {
#   role       = aws_iam_role.github_<repo_name>.name
#   policy_arn = "<appropriate_policy_arn_for_that_repo>"
# }
# ------------------------------------------------------------------------------
