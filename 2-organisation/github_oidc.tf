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
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]

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
# IAM Role — aws-shared-services-infra
#
# This is a management-account gateway role for the shared-services Terraform
# repo. GitHub assumes this role first using OIDC. The inline policy below then
# allows this role to assume OrganizationAccountAccessRole in the shared-services
# account, where the actual shared infrastructure is deployed.
#
# Flow:
#   GitHub aws-shared-services-infra
#     -> management account gateway role
#     -> shared-services OrganizationAccountAccessRole
#     -> TGW, RAM share, ECR, Route 53, shared platform resources
# ------------------------------------------------------------------------------

resource "aws_iam_role" "github_aws_shared_services_infra" {
  name        = "github-actions-aws-shared-services-infra"
  description = "Gateway role assumed by GitHub Actions in the aws-shared-services-infra repo."

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
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_shared_services_repo}:*"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Allow the shared-services gateway role to enter only the shared-services
# account. The target role is the Organizations-created admin role for this POC.
resource "aws_iam_role_policy" "github_aws_shared_services_infra_assume_role" {
  name = "AssumeSharedServicesAccount"
  role = aws_iam_role.github_aws_shared_services_infra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeSharedServicesAccount"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::${var.shared_services_account_id}:role/OrganizationAccountAccessRole"
        ]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# IAM Role — aws-sandbox-infra
#
# This is a management-account gateway role for the sandbox Terraform repo.
# GitHub assumes this role first using OIDC. The inline policy below then allows
# this role to assume OrganizationAccountAccessRole in the sandbox account, where
# sandbox infrastructure such as VPC, EKS, ALB and TGW attachments are deployed.
#
# Flow:
#   GitHub aws-sandbox-infra
#     -> management account gateway role
#     -> sandbox OrganizationAccountAccessRole
#     -> sandbox workload/networking resources
# ------------------------------------------------------------------------------

resource "aws_iam_role" "github_aws_sandbox_infra" {
  name        = "github-actions-aws-sandbox-infra"
  description = "Gateway role assumed by GitHub Actions in the aws-sandbox-infra repo."

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
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_sandbox_repo}:*"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Allow the sandbox gateway role to enter only the Terraform-managed sandbox
# account. The target role is the Organizations-created admin role for this POC.
resource "aws_iam_role_policy" "github_aws_sandbox_infra_assume_role" {
  name = "AssumeSandboxAccount"
  role = aws_iam_role.github_aws_sandbox_infra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeSandboxAccount"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::${aws_organizations_account.sandbox.id}:role/OrganizationAccountAccessRole"
        ]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# IAM Role — aws-security-infra
#
# Gateway role for the security-infra Terraform repo.
# Unlike shared-services and sandbox which each target one account, this role
# must assume into TWO accounts — log-archive and audit — because aws-security-infra
# manages both from a single Terraform root using provider aliases.
#
# Flow:
#   GitHub aws-security-infra
#     -> management account gateway role
#     -> log-archive OrganizationAccountAccessRole  (S3 bucket, Object Lock)
#     -> audit OrganizationAccountAccessRole        (GuardDuty + Security Hub delegated admin)
# ------------------------------------------------------------------------------

resource "aws_iam_role" "github_aws_security_infra" {
  name        = "github-actions-aws-security-infra"
  description = "Gateway role assumed by GitHub Actions in the aws-security-infra repo."

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
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_org}/${var.github_security_infra_repo}:*"
          }
        }
      }
    ]
  })

  tags = var.tags
}

# Allow the security-infra gateway role to assume into both security accounts.
# log-archive: owns the immutable S3 bucket and receives CloudTrail + Config data.
# audit: owns GuardDuty and Security Hub delegated admin.
resource "aws_iam_role_policy" "github_aws_security_infra_assume_role" {
  name = "AssumeSecurityAccounts"
  role = aws_iam_role.github_aws_security_infra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AssumeSecurityAccounts"
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Resource = [
          "arn:aws:iam::${aws_organizations_account.log_archive.id}:role/OrganizationAccountAccessRole",
          "arn:aws:iam::${aws_organizations_account.audit.id}:role/OrganizationAccountAccessRole"
        ]
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# Terraform state backend access — one policy per downstream repo
#
# Every downstream gateway role needs S3 + DynamoDB permissions to run
# terraform init. The backend (S3 bucket + DynamoDB lock table) lives in the
# management account and uses the ambient OIDC role credentials — not the
# assume_role credentials used for the target account. Without these policies,
# terraform init fails with AccessDenied on s3:ListBucket.
#
# Each policy is scoped to only that repo's state key prefix so repos cannot
# read or overwrite each other's state.
# ------------------------------------------------------------------------------

resource "aws_iam_role_policy" "github_aws_shared_services_infra_tf_state" {
  name = "TerraformStateAccess"
  role = aws_iam_role.github_aws_shared_services_infra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListTerraformStateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::loadberry-org-tf-state-eu-west-2"
      },
      {
        Sid    = "ReadWriteState"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::loadberry-org-tf-state-eu-west-2/shared-services/*"
      },
      {
        Sid    = "StateLocks"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:eu-west-2:${var.management_account_id}:table/loadberry-org-tf-locks"
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_aws_sandbox_infra_tf_state" {
  name = "TerraformStateAccess"
  role = aws_iam_role.github_aws_sandbox_infra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListTerraformStateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::loadberry-org-tf-state-eu-west-2"
      },
      {
        Sid    = "ReadWriteState"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::loadberry-org-tf-state-eu-west-2/sandbox/*"
      },
      {
        Sid    = "StateLocks"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:eu-west-2:${var.management_account_id}:table/loadberry-org-tf-locks"
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_aws_security_infra_tf_state" {
  name = "TerraformStateAccess"
  role = aws_iam_role.github_aws_security_infra.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListTerraformStateBucket"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = "arn:aws:s3:::loadberry-org-tf-state-eu-west-2"
      },
      {
        Sid    = "ReadWriteState"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = "arn:aws:s3:::loadberry-org-tf-state-eu-west-2/security/*"
      },
      {
        Sid    = "StateLocks"
        Effect = "Allow"
        Action = [
          "dynamodb:DescribeTable",
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:DeleteItem",
          "dynamodb:UpdateItem"
        ]
        Resource = "arn:aws:dynamodb:eu-west-2:${var.management_account_id}:table/loadberry-org-tf-locks"
      }
    ]
  })
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
