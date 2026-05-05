# ------------------------------------------------------------------------------
# IAM Identity Center (SSO)
#
# All human access to AWS goes through Identity Center — no IAM users anywhere.
# One login → access any account you're assigned to.
# One place to add/remove people across the whole organisation.
# One audit log for all human access.
#
# How it works:
#   1. Identity Center instance is enabled (one per org)
#   2. Permission sets define WHAT someone can do (like an IAM role template)
#   3. Assignments connect a USER + PERMISSION SET + ACCOUNT
#
# We create the instance and permission sets here.
# Assignments are added after SSO users exist.
# ------------------------------------------------------------------------------

# Read the Identity Center instance — created when you enable Identity Center
# in the console or via AWS (one instance per organisation, always index [0]).
data "aws_ssoadmin_instances" "this" {}

locals {
  sso_instance_arn = tolist(data.aws_ssoadmin_instances.this.arns)[0]
}

# ------------------------------------------------------------------------------
# Permission Set 1 — AdministratorAccess
#
# Full admin access. Used by the org owner/platform team.
# Session capped at 4 hours — forces re-authentication regularly.
# Short sessions limit the damage window if credentials are compromised.
# ------------------------------------------------------------------------------

resource "aws_ssoadmin_permission_set" "admin" {
  name             = "AdministratorAccess"
  description      = "Full administrative access. Platform team only."
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"

  tags = var.tags
}

resource "aws_ssoadmin_managed_policy_attachment" "admin" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ------------------------------------------------------------------------------
# Permission Set 2 — ReadOnlyAccess
#
# Read everything, change nothing. For auditors or engineers
# who need visibility without the ability to make changes.
# Longer session (8 hours) — read-only access is lower risk.
# ------------------------------------------------------------------------------

resource "aws_ssoadmin_permission_set" "read_only" {
  name             = "ReadOnlyAccess"
  description      = "Read-only access across all services. For auditors and observers."
  instance_arn     = local.sso_instance_arn
  session_duration = "PT8H"

  tags = var.tags
}

resource "aws_ssoadmin_managed_policy_attachment" "read_only" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.read_only.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# ------------------------------------------------------------------------------
# Permission Set 3 — DeployAccess
#
# Scoped permissions for deployment pipelines and CI/CD roles.
# Only the specific actions needed to push images and update services.
# Short session (1 hour) — deploy sessions should be brief and targeted.
#
# Allows:
#   ECR   — push/pull container images
#   ECS   — update services and register task definitions
#   S3    — read/write deploy artefact buckets
#   Secrets Manager — read secrets needed at deploy time
# ------------------------------------------------------------------------------

resource "aws_ssoadmin_permission_set" "deploy" {
  name             = "DeployAccess"
  description      = "Scoped deploy permissions for CI/CD pipelines."
  instance_arn     = local.sso_instance_arn
  session_duration = "PT1H"

  tags = var.tags
}

resource "aws_ssoadmin_permission_set_inline_policy" "deploy" {
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.deploy.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ECRAccess"
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
          "ecr:BatchCheckLayerAvailability"
        ]
        Resource = "*"
      },
      {
        Sid    = "ECSAccess"
        Effect = "Allow"
        Action = [
          "ecs:UpdateService",
          "ecs:RegisterTaskDefinition",
          "ecs:DescribeServices",
          "ecs:DescribeTaskDefinition"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3DeployBuckets"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ]
        # Scope this to specific deploy bucket ARNs in production
        Resource = "*"
      },
      {
        Sid    = "SecretsAccess"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        # Scope this to specific secret ARNs in production
        Resource = "*"
      }
    ]
  })
}

# ------------------------------------------------------------------------------
# User Assignments — add after SSO users exist
#
# Pattern:
#   resource "aws_ssoadmin_account_assignment" "your_name_admin" {
#     instance_arn       = local.sso_instance_arn
#     permission_set_arn = aws_ssoadmin_permission_set.admin.arn
#
#     principal_type = "USER"
#     principal_id   = "<user_id_from_identity_center>"
#
#     target_type = "AWS_ACCOUNT"
#     target_id   = var.management_account_id
#   }
#
# To get the user ID:
#   aws identitystore list-users \
#     --identity-store-id <id_from_identity_center_console>
# ------------------------------------------------------------------------------
