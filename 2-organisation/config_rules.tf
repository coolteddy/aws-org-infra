# ------------------------------------------------------------------------------
# AWS Config Organisation Rules
#
# These are organisation-level managed rules — deployed once from the
# management account and automatically applied to every account in the org,
# regardless of how the account was created (AFT, CLI, or console).
#
# Config rules vs SCPs:
#   SCP    = prevents the action  (hard block at API level, real-time)
#   Config = detects non-compliance (reports after the fact, flags resources)
#   Use both together — SCPs prevent, Config catches anything that slips through.
#
# STATUS: COMMENTED OUT — pending Config recorder setup
#
# REASON: aws_config_organization_managed_rule requires a Config recorder
# to be running in every target account and region before rules can evaluate.
# Config recorder is per account, per region — there is no org-wide recorder.
# Neither the management account nor Burmanic have recorders enabled.
#
# HOW TO ENABLE (three options — see README.md Config Rules section):
#   Option A: AWS Systems Manager Quick Setup (fastest — no code needed)
#   Option B: CloudFormation StackSets (code-driven, all accounts/regions)
#   Option C: AFT global customisations (automatic for all future accounts)
#
# WHEN TO UNCOMMENT:
#   1. Enable Config recorder in all target accounts (see README.md)
#   2. Uncomment the resource blocks below
#   3. Run: terraform apply -target=aws_config_organization_managed_rule.*
# ------------------------------------------------------------------------------

# ------------------------------------------------------------------------------
# Rule 1 — RDS Instance Public Access Check
#
# Complements the DenyRDSPublicAccess SCP.
# SCP tries to prevent it — this rule catches it if it exists.
# Flags any RDS instance where PubliclyAccessible = true.
# ------------------------------------------------------------------------------

# resource "aws_config_organization_managed_rule" "rds_public_access" {
#   name            = "rds-instance-public-access-check"
#   rule_identifier = "RDS_INSTANCE_PUBLIC_ACCESS_CHECK"
#   description     = "Checks that RDS instances do not allow public access."
#
#   # Exclude accounts without Config recorder enabled:
#   # excluded_accounts = ["YOUR_ACCOUNT_ID_TO_EXCLUDE"]
# }

# ------------------------------------------------------------------------------
# Rule 2 — S3 Bucket Public Read Prohibited
#
# Complements the DenyPublicS3 SCP.
# Detects any S3 bucket that allows public read access via ACL or bucket policy.
# ------------------------------------------------------------------------------

# resource "aws_config_organization_managed_rule" "s3_public_read" {
#   name            = "s3-bucket-public-read-prohibited"
#   rule_identifier = "S3_BUCKET_PUBLIC_READ_PROHIBITED"
#   description     = "Checks that S3 buckets do not allow public read access."
#
#   # excluded_accounts = ["YOUR_ACCOUNT_ID_TO_EXCLUDE"]
# }

# ------------------------------------------------------------------------------
# Rule 3 — S3 Bucket Public Write Prohibited
#
# Detects any S3 bucket that allows public write access.
# Public write = anyone on the internet can upload objects to your bucket.
# ------------------------------------------------------------------------------

# resource "aws_config_organization_managed_rule" "s3_public_write" {
#   name            = "s3-bucket-public-write-prohibited"
#   rule_identifier = "S3_BUCKET_PUBLIC_WRITE_PROHIBITED"
#   description     = "Checks that S3 buckets do not allow public write access."
#
#   # excluded_accounts = ["YOUR_ACCOUNT_ID_TO_EXCLUDE"]
# }

# ------------------------------------------------------------------------------
# Rule 4 — Root Account MFA Enabled
#
# The root user has unlimited access to the account.
# MFA on root is non-negotiable. This rule flags any account where
# the root user does not have MFA enabled.
# ------------------------------------------------------------------------------

# resource "aws_config_organization_managed_rule" "root_mfa_enabled" {
#   name            = "root-account-mfa-enabled"
#   rule_identifier = "ROOT_ACCOUNT_MFA_ENABLED"
#   description     = "Checks that the root account has MFA enabled."
#
#   # excluded_accounts = ["YOUR_ACCOUNT_ID_TO_EXCLUDE"]
# }

# ------------------------------------------------------------------------------
# Rule 5 — Root Access Key Check
#
# Root should never have programmatic access keys.
# If root has access keys, a leaked key = full account compromise.
# This flags any account where root access keys exist.
# ------------------------------------------------------------------------------

# resource "aws_config_organization_managed_rule" "root_access_key_check" {
#   name            = "iam-root-access-key-check"
#   rule_identifier = "IAM_ROOT_ACCESS_KEY_CHECK"
#   description     = "Checks that the root account has no active access keys."
#
#   # excluded_accounts = ["YOUR_ACCOUNT_ID_TO_EXCLUDE"]
# }

# ------------------------------------------------------------------------------
# Rule 6 — EBS Volume Encryption
#
# All EBS volumes (disks attached to EC2 instances) must be encrypted.
# Unencrypted volumes are a data breach risk if snapshots are shared
# or volumes are detached and accessed by another account.
# ------------------------------------------------------------------------------

# resource "aws_config_organization_managed_rule" "encrypted_volumes" {
#   name            = "encrypted-volumes"
#   rule_identifier = "ENCRYPTED_VOLUMES"
#   description     = "Checks that EBS volumes attached to EC2 instances are encrypted."
#
#   # excluded_accounts = ["YOUR_ACCOUNT_ID_TO_EXCLUDE"]
# }
