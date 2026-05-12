# ------------------------------------------------------------------------------
# Global SCPs — attached to Root
# These apply to EVERY account in the organisation automatically.
# SCPs do not grant permissions — they set the maximum permissions ceiling.
# An SCP Deny overrides any IAM Allow, no exceptions.
#
# AWS hard limit: 5 SCPs per target (Root, OU, or account).
# The default FullAWSAccess SCP counts as 1, leaving 4 slots for our SCPs.
#
# Structure:
#   1. DenyUnsupportedRegions        ← region guardrail
#   2. DenyIAMUserCreation           ← SSO-only access
#   3. DenySecurityMonitoringDisable ← CloudTrail + GuardDuty + Config (merged)
#   4. DenyPublicS3                  ← data protection
# ------------------------------------------------------------------------------

locals {
  root_id = data.aws_organizations_organization.this.roots[0].id
}

# ------------------------------------------------------------------------------
# SCP 1 — Deny Unsupported Regions
#
# Blocks any AWS action outside the approved region list.
#
# Uses NotAction instead of Action — because some services are global
# (IAM, STS, Route53, CloudFront, ACM) and don't operate in a specific region.
# If we blocked Action: "*", we'd break those global services.
# ACM is included because CloudFront certificates must be provisioned in us-east-1
# regardless of where workloads run — without this exemption, acm:RequestCertificate
# in us-east-1 would be denied.
# NotAction means: "deny everything EXCEPT this list of global services".
# ------------------------------------------------------------------------------

resource "aws_organizations_policy" "deny_unsupported_regions" {
  name        = "DenyUnsupportedRegions"
  description = "Blocks all actions outside approved regions. Global services are excluded."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyUnsupportedRegions"
        Effect = "Deny"
        NotAction = [
          "iam:*",
          "sts:*",
          "support:*",
          "trustedadvisor:*",
          "cloudfront:*",
          "acm:*",
          "route53:*",
          "route53domains:*",
          "budgets:*",
          "ce:*",
          "organizations:*",
          "account:*",
          "health:*",
          "waf:*"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = [
              "eu-west-2",
              "ap-southeast-2"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "deny_unsupported_regions" {
  policy_id = aws_organizations_policy.deny_unsupported_regions.id
  target_id = local.root_id
}

# ------------------------------------------------------------------------------
# SCP 2 — Deny IAM User Creation
#
# All human access must go through IAM Identity Center (SSO).
# No standalone IAM users or programmatic access keys are allowed anywhere.
# ------------------------------------------------------------------------------

resource "aws_organizations_policy" "deny_iam_user_creation" {
  name        = "DenyIAMUserCreation"
  description = "Blocks creation of IAM users and access keys. SSO is the only permitted access method."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyIAMUserCreation"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:CreateAccessKey"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "deny_iam_user_creation" {
  policy_id = aws_organizations_policy.deny_iam_user_creation.id
  target_id = local.root_id
}

# ------------------------------------------------------------------------------
# SCP 3 — Deny Security Monitoring Disable
#
# Consolidated from three separate SCPs to stay within AWS's hard limit
# of 5 SCPs per target (FullAWSAccess counts as 1, leaving 4 slots).
#
# Covers three security monitoring services in one policy:
#
# CloudTrail — records every API call. The organisation's audit trail.
#              Must never be stopped or modified.
#
# GuardDuty  — monitors for threats across all accounts.
#              Disabling it is a common attacker technique post-compromise.
#
# Config     — tracks all resource configuration changes.
#              Without it, compliance rules go blind.
# ------------------------------------------------------------------------------

resource "aws_organizations_policy" "deny_security_monitoring_disable" {
  name        = "DenySecurityMonitoringDisable"
  description = "Prevents CloudTrail, GuardDuty, and AWS Config from being disabled. Consolidated to stay within the 5-SCP-per-target limit."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyCloudTrailDisable"
        Effect = "Deny"
        Action = [
          "cloudtrail:DeleteTrail",
          "cloudtrail:StopLogging",
          "cloudtrail:UpdateTrail",
          "cloudtrail:PutEventSelectors"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyGuardDutyDisable"
        Effect = "Deny"
        Action = [
          "guardduty:DeleteDetector",
          "guardduty:DisassociateFromMasterAccount",
          "guardduty:DisassociateFromAdministratorAccount",
          "guardduty:StopMonitoringMembers",
          "guardduty:UpdateDetector"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyConfigDisable"
        Effect = "Deny"
        Action = [
          "config:StopConfigurationRecorder",
          "config:DeleteConfigurationRecorder",
          "config:DeleteDeliveryChannel"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "deny_security_monitoring_disable" {
  policy_id = aws_organizations_policy.deny_security_monitoring_disable.id
  target_id = local.root_id
}

# ------------------------------------------------------------------------------
# SCP 4 — Deny Public S3
#
# Prevents S3 buckets and objects from being made publicly accessible.
# Public S3 buckets are one of the most common causes of data breaches.
# This blocks setting public ACLs at both bucket and object level.
# ------------------------------------------------------------------------------

resource "aws_organizations_policy" "deny_public_s3" {
  name        = "DenyPublicS3"
  description = "Blocks setting public ACLs on S3 buckets and objects."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyPublicS3"
        Effect = "Deny"
        Action = [
          "s3:PutBucketAcl",
          "s3:PutObjectAcl"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "s3:x-amz-acl" = [
              "public-read",
              "public-read-write",
              "authenticated-read"
            ]
          }
        }
      }
    ]
  })
}

resource "aws_organizations_policy_attachment" "deny_public_s3" {
  policy_id = aws_organizations_policy.deny_public_s3.id
  target_id = local.root_id
}
