# ------------------------------------------------------------------------------
# Workloads OU SCPs — attached to the Workloads OU only
# These apply to all tenant accounts inside Workloads OU and any child OUs.
# They do NOT apply to Security or Shared OUs.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# SCP 1 — Deny Cross-Tenant VPC Peering
#
# Tenants must never be able to reach each other's networks.
# AcceptVpcPeeringConnection is the action that completes a peering request.
# Even if a tenant initiates a peering request, this SCP makes acceptance
# impossible — the isolation is enforced at the AWS API level.
# ------------------------------------------------------------------------------

resource "aws_organizations_policy" "deny_cross_tenant_vpc_peering" {
  name        = "DenyCrossTenantVpcPeering"
  description = "Prevents tenant accounts from accepting VPC peering connections. Enforces network isolation between tenants."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "DenyCrossTenantVpcPeering"
        Effect   = "Deny"
        Action   = ["ec2:AcceptVpcPeeringConnection"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "deny_cross_tenant_vpc_peering" {
  policy_id = aws_organizations_policy.deny_cross_tenant_vpc_peering.id
  target_id = aws_organizations_organizational_unit.workloads.id
}

# ------------------------------------------------------------------------------
# SCP 2 — Require Mandatory Tags
#
# Blocks creating key resources without required tags.
# Tags are how we track cost per tenant and per environment.
#
# Why separate statements per tag:
# A single Null condition with multiple keys only triggers when ALL tags
# are missing simultaneously. To catch each missing tag individually,
# each required tag needs its own Deny statement.
#
# Note: This SCP covers the most common resource types. For comprehensive
# tag enforcement across all services, pair this with AWS Config Rules.
# ------------------------------------------------------------------------------

resource "aws_organizations_policy" "require_mandatory_tags" {
  name        = "RequireMandatoryTags"
  description = "Blocks creating key resources without required tags: tenant, environment, project."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyIfMissingTenantTag"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "rds:CreateDBInstance",
          "rds:CreateDBCluster",
          "s3:CreateBucket",
          "ecs:CreateCluster",
          "ecs:CreateService",
          "lambda:CreateFunction",
          "eks:CreateCluster"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:RequestTag/tenant" = "true"
          }
        }
      },
      {
        Sid    = "DenyIfMissingEnvironmentTag"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "rds:CreateDBInstance",
          "rds:CreateDBCluster",
          "s3:CreateBucket",
          "ecs:CreateCluster",
          "ecs:CreateService",
          "lambda:CreateFunction",
          "eks:CreateCluster"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:RequestTag/environment" = "true"
          }
        }
      },
      {
        Sid    = "DenyIfMissingProjectTag"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "rds:CreateDBInstance",
          "rds:CreateDBCluster",
          "s3:CreateBucket",
          "ecs:CreateCluster",
          "ecs:CreateService",
          "lambda:CreateFunction",
          "eks:CreateCluster"
        ]
        Resource = "*"
        Condition = {
          Null = {
            "aws:RequestTag/project" = "true"
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "require_mandatory_tags" {
  policy_id = aws_organizations_policy.require_mandatory_tags.id
  target_id = aws_organizations_organizational_unit.workloads.id
}
