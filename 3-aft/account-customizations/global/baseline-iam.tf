# ============================================================
# Account Customisation — Baseline IAM + Config Recorder
# STATUS: CODE ONLY — DO NOT APPLY IN POC
#
# This runs automatically in every account vended by AFT.
#
# This file does two things:
#   1. Sets the IAM password policy for any IAM users in this account
#      (even though our SCP blocks creating IAM users, this is a
#      defence-in-depth measure for the management account itself)
#
#   2. Enables the AWS Config recorder so that:
#      - Config rules can evaluate resources in this account
#      - Organisation Config rules (from 2-organisation/) work here
#      - Resource configuration history is tracked for auditing
#
# This file solves the Config recorder prerequisite problem:
# without it, org Config rules show "NoAvailableConfigurationRecorder".
# ============================================================

# ---- IAM Password Policy ----
# Sets minimum security requirements for IAM user passwords.
# resource "aws_iam_account_password_policy" "this" {
#   minimum_password_length        = 14
#   require_symbols                = true
#   require_numbers                = true
#   require_uppercase_characters   = true
#   require_lowercase_characters   = true
#   allow_users_to_change_password = true
#   max_password_age               = 90   # days before password expires
#   password_reuse_prevention      = 24   # cannot reuse last 24 passwords
#   hard_expiry                    = false # don't lock out expired accounts
# }

# ---- AWS Config Recorder ----
# The recorder tracks every resource configuration change in this account.
# Without this, Config rules cannot evaluate anything.

# IAM role that allows Config to read resources in this account.
# resource "aws_iam_role" "config_recorder" {
#   name = "aws-config-recorder-role"
#
#   assume_role_policy = jsonencode({
#     Version = "2012-10-17"
#     Statement = [{
#       Effect    = "Allow"
#       Principal = { Service = "config.amazonaws.com" }
#       Action    = "sts:AssumeRole"
#     }]
#   })
# }

# resource "aws_iam_role_policy_attachment" "config_recorder" {
#   role       = aws_iam_role.config_recorder.name
#   policy_arn = "arn:aws:iam::aws:policy/service-role/AWS_ConfigRole"
# }

# S3 bucket in the log-archive account receives Config snapshots.
# The bucket name follows the pattern set by Control Tower.
# resource "aws_config_configuration_recorder" "this" {
#   name     = "default"
#   role_arn = aws_iam_role.config_recorder.arn
#
#   recording_group {
#     all_supported                 = true
#     include_global_resource_types = true
#   }
# }

# Delivery channel — where Config sends its recordings.
# resource "aws_config_delivery_channel" "this" {
#   name           = "default"
#   s3_bucket_name = "aws-controltower-logs-${var.management_account_id}-eu-west-2"
#
#   depends_on = [aws_config_configuration_recorder.this]
# }

# Start the recorder — Config recording is off by default.
# resource "aws_config_configuration_recorder_status" "this" {
#   name       = aws_config_configuration_recorder.this.name
#   is_enabled = true
#
#   depends_on = [aws_config_delivery_channel.this]
# }
