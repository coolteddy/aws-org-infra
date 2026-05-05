# ============================================================
# Account Customisation — GuardDuty
# STATUS: CODE ONLY — DO NOT APPLY IN POC
#
# This runs automatically in every account vended by AFT.
#
# GuardDuty is AWS's threat detection service. It analyses:
#   - CloudTrail logs  (who did what, from where)
#   - VPC Flow Logs    (network traffic patterns)
#   - DNS logs         (domain lookups — detects malware beaconing)
#
# It uses machine learning to detect:
#   - Compromised credentials (unusual API calls, new regions)
#   - Cryptocurrency mining (high CPU, unusual network)
#   - Malware communication (known bad domains/IPs)
#   - Data exfiltration (large unexpected data transfers)
#
# Cost: first 30 days free per account, then based on data volume.
# Typically $1-3/month for a small idle account.
# ============================================================

# Enable GuardDuty in this account
# resource "aws_guardduty_detector" "this" {
#   enable = true
#
#   # Check for new findings every 15 minutes (options: 1h, 6h, 15min)
#   # 15 minutes gives fastest alerting — recommended for production.
#   finding_publishing_frequency = "FIFTEEN_MINUTES"
# }

# Accept the delegated admin invitation from the audit account.
# The audit account acts as the central GuardDuty administrator —
# all findings from all accounts aggregate there for a single pane of glass.
# resource "aws_guardduty_member" "this" {
#   account_id  = data.aws_caller_identity.current.account_id
#   detector_id = aws_guardduty_detector.this.id
#   email       = var.admin_email
#   invite      = true
# }

# data "aws_caller_identity" "current" {}
