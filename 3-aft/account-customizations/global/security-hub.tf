# ============================================================
# Account Customisation — Security Hub
# STATUS: CODE ONLY — DO NOT APPLY IN POC
#
# This runs automatically in every account vended by AFT.
#
# Security Hub is AWS's compliance and security posture service.
# Think of it as a dashboard that aggregates security findings
# from multiple services into one place:
#   - GuardDuty findings
#   - Config rule violations
#   - Inspector vulnerability findings
#   - IAM Access Analyzer findings
#
# It also runs its own checks against compliance standards
# (see below) and scores your account's security posture.
#
# Key concept — Security Hub does NOT prevent anything.
# It DETECTS and REPORTS. SCPs prevent, Security Hub reports.
#
# Cost: $0.0010 per security check per account per month.
# Roughly $1-5/month for a small account.
# ============================================================

# Enable Security Hub in this account
# resource "aws_securityhub_account" "this" {}

# ---- Compliance Standards ----
# These are pre-built rule sets that Security Hub evaluates against.
# Each standard runs hundreds of checks automatically.

# Standard 1: AWS Foundational Security Best Practices
# AWS's own opinionated security checklist covering ~200 controls.
# Examples: MFA on root, no public S3, encrypted EBS, no unused IAM users.
# resource "aws_securityhub_standards_subscription" "aws_foundational" {
#   depends_on    = [aws_securityhub_account.this]
#   standards_arn = "arn:aws:securityhub:eu-west-2::standards/aws-foundational-security-best-practices/v/1.0.0"
# }

# Standard 2: CIS AWS Foundations Benchmark
# Industry standard checklist published by the Center for Internet Security.
# Commonly required for SOC 2, ISO 27001, and enterprise security audits.
# resource "aws_securityhub_standards_subscription" "cis" {
#   depends_on    = [aws_securityhub_account.this]
#   standards_arn = "arn:aws:securityhub:eu-west-2::standards/cis-aws-foundations-benchmark/v/1.4.0"
# }
