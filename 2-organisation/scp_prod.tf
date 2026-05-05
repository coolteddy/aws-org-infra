# ------------------------------------------------------------------------------
# Prod SCPs — attach to production accounts only
#
# These do NOT attach to Root or Workloads OU because they would break
# dev and staging environments (e.g. dev legitimately deletes RDS snapshots).
#
# How to attach when prod accounts exist — two options:
#
# Option A: Attach to a dedicated Prod OU inside each Tenant OU
#   target_id = aws_organizations_organizational_unit.tenant_a_prod.id
#
# Option B: Attach directly to a specific prod account ID
#   target_id = "123456789012"   (the prod account ID)
#
# For the POC: policies are created (free, no impact), attachments are
# added when prod accounts are provisioned.
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# SCP 1 — Deny RDS Backup Deletion
#
# Production databases must always have a recovery point.
# This blocks deleting manual snapshots, cluster snapshots, and
# disabling the automated backup window on any RDS instance.
# ------------------------------------------------------------------------------

resource "aws_organizations_policy" "deny_rds_backup_deletion" {
  name        = "DenyRDSBackupDeletion"
  description = "Prevents deletion of RDS snapshots and disabling of automated backups in production."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyRDSBackupDeletion"
        Effect = "Deny"
        Action = [
          "rds:DeleteDBSnapshot",
          "rds:DeleteDBClusterSnapshot",
          "rds:ModifyDBInstance",
          "rds:ModifyDBCluster"
        ]
        Resource = "*"
        Condition = {
          # Only block the modify actions when they're disabling backups.
          # Allows other ModifyDBInstance changes (e.g. instance type upgrades).
          NumericEquals = {
            "rds:BackupRetentionPeriod" = 0
          }
        }
      },
      {
        # DeleteDBSnapshot and DeleteDBClusterSnapshot have no condition —
        # snapshot deletion is always blocked in prod regardless of reason.
        Sid    = "DenyRDSSnapshotDeletion"
        Effect = "Deny"
        Action = [
          "rds:DeleteDBSnapshot",
          "rds:DeleteDBClusterSnapshot"
        ]
        Resource = "*"
      }
    ]
  })
}

# Uncomment and set target_id when prod accounts are provisioned:
# resource "aws_organizations_policy_attachment" "deny_rds_backup_deletion" {
#   policy_id = aws_organizations_policy.deny_rds_backup_deletion.id
#   target_id = "<prod_account_id_or_prod_ou_id>"
# }

# ------------------------------------------------------------------------------
# SCP 2 — Deny RDS Public Access
#
# Production databases must never have a public endpoint.
# This blocks the PubliclyAccessible flag from being set to true
# on any RDS instance or cluster modification.
# ------------------------------------------------------------------------------

resource "aws_organizations_policy" "deny_rds_public_access" {
  name        = "DenyRDSPublicAccess"
  description = "Prevents RDS instances from being made publicly accessible in production."
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyRDSPublicAccess"
        Effect = "Deny"
        Action = [
          "rds:CreateDBInstance",
          "rds:ModifyDBInstance",
          "rds:CreateDBCluster",
          "rds:ModifyDBCluster"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "rds:req-tag/publicly-accessible" = "true"
          }
        }
      }
    ]
  })
}

# Uncomment and set target_id when prod accounts are provisioned:
# resource "aws_organizations_policy_attachment" "deny_rds_public_access" {
#   policy_id = aws_organizations_policy.deny_rds_public_access.id
#   target_id = "<prod_account_id_or_prod_ou_id>"
# }


# Option A — Attach directly to the prod account ID
# resource "aws_organizations_policy_attachment" "deny_rds_backup_deletion" {
#   policy_id = aws_organizations_policy.deny_rds_backup_deletion.id
#   target_id = "123456789012"  # prod account ID
# }
# Simple. No OU restructure needed.

# Option B — Add a Prod sub-OU under each Tenant OU
# Tenant-A OU
# ├── tenant-a-dev      (account)
# ├── tenant-a-staging  (account)
# └── Prod OU           ← SCP attaches here
#     └── tenant-a-prod (account)
# More structure, but scales better across multiple tenants.