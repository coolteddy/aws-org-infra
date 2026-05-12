# Security Infrastructure Test Plan

> This file is also kept in `aws-security-infra/SECURITY-INFRA-TEST-PLAN.md` — that is the primary copy.


End-to-end test for the `aws-security-infra` repo.
Validates log-archive (immutable audit trail) and audit (security monitoring hub) accounts.
Total cost: ~$0.50. Total time: ~2 hours including build and validation.

---

## What We Are Testing

```
Management account
  └── Org-level CloudTrail ──────────────────────────────────────┐
                                                                  ↓
log-archive account                                    S3 bucket (Object Lock)
  └── Receives CloudTrail logs from all accounts ───────────────┘

audit account
  └── GuardDuty delegated admin  ← aggregates findings from all accounts
  └── Security Hub delegated admin ← aggregates findings from all accounts

sandbox account
  └── GuardDuty enabled ──────────────────────────────────────────→ audit
  └── Security Hub enabled ─────────────────────────────────────→ audit
  └── Config recorder started
```

---

## Cost

| Resource | Cost | Notes |
|---|---|---|
| GuardDuty (log-archive, audit, sandbox) | $0 | 30-day free trial per account |
| Security Hub (log-archive, audit, sandbox) | $0 | 30-day free trial per account |
| Config recorder (sandbox) | ~$0.50 | ~100 config items × $0.003. Stop after test. |
| CloudTrail org trail | $0 | Management events free on first trail |
| S3 log storage | ~$0.01 | Tiny volume at POC scale |
| **Total** | **~$0.50** | |

> Test within 30 days of account creation to stay within the free trial window.

---

## Pre-Flight Checklist (do before building anything)

### 1. Create accounts in aws-org-infra

Add to `2-organisation/accounts.tf` and open a PR:

```hcl
resource "aws_organizations_account" "log_archive" {
  name      = "log-archive"
  email     = var.log_archive_email   # e.g. aws+log-archive@yourdomain.com
  parent_id = aws_organizations_organizational_unit.security.id
  close_on_deletion = false
  lifecycle { prevent_destroy = true }
  tags = { environment = "security", managed_by = "terraform" }
}

resource "aws_organizations_account" "audit" {
  name      = "audit"
  email     = var.audit_email         # e.g. aws+audit@yourdomain.com
  parent_id = aws_organizations_organizational_unit.security.id
  close_on_deletion = false
  lifecycle { prevent_destroy = true }
  tags = { environment = "security", managed_by = "terraform" }
}
```

### 2. Update CIDR.md

Mark the following as allocated:

| CIDR | Account |
|---|---|
| `10.3.0.0/16` | log-archive |
| `10.4.0.0/16` | audit |

> Note: neither account needs a VPC for this test. CIDRs reserved for future use only.

### 3. Add OIDC roles in aws-org-infra

Add to `2-organisation/github_oidc.tf` — one role per account:

```hcl
# Role for aws-security-infra to deploy into log-archive account
resource "aws_iam_role" "github_aws_security_infra_log_archive" { ... }

# Role for aws-security-infra to deploy into audit account
resource "aws_iam_role" "github_aws_security_infra_audit" { ... }
```

### 4. Enable RAM org sharing (if not already done)

```bash
aws configure list-profiles
aws ram enable-sharing-with-aws-organization --profile <management-profile>
```

Check: RAM console → Settings → "Sharing with AWS Organizations" = Enabled.

---

## Build Sequence

### Step 1 — log-archive account: S3 bucket with Object Lock

```hcl
resource "aws_s3_bucket" "log_archive" {
  provider = aws.log_archive
  bucket   = "loadberry-log-archive-eu-west-2"

  object_lock_enabled = true   # must be set at creation, cannot add later

  lifecycle { prevent_destroy = true }
}

resource "aws_s3_bucket_object_lock_configuration" "log_archive" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.log_archive.id

  rule {
    default_retention {
      mode = "GOVERNANCE"   # POC ONLY — switch to COMPLIANCE for production
      days = 7              # short retention for POC cleanup
    }
  }
}

resource "aws_s3_bucket_versioning" "log_archive" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.log_archive.id
  versioning_configuration { status = "Enabled" }  # required for Object Lock
}

resource "aws_s3_bucket_server_side_encryption_configuration" "log_archive" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.log_archive.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# Bucket policy: allow CloudTrail to write, deny all deletes
resource "aws_s3_bucket_policy" "log_archive" {
  provider = aws.log_archive
  bucket   = aws_s3_bucket.log_archive.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCloudTrailWrite"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.log_archive.arn}/AWSLogs/*"
        Condition = {
          StringEquals = { "s3:x-amz-acl" = "bucket-owner-full-control" }
        }
      },
      {
        Sid    = "AllowCloudTrailBucketCheck"
        Effect = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.log_archive.arn
      },
      {
        Sid       = "DenyDelete"
        Effect    = "Deny"
        Principal = "*"
        Action    = ["s3:DeleteObject", "s3:DeleteObjectVersion", "s3:DeleteBucket"]
        Resource  = [
          aws_s3_bucket.log_archive.arn,
          "${aws_s3_bucket.log_archive.arn}/*"
        ]
      }
    ]
  })
}
```

---

### Step 2 — management account: Org-level CloudTrail

```hcl
resource "aws_cloudtrail" "org" {
  provider                      = aws.management
  name                          = "loadberry-org-trail"
  s3_bucket_name                = "loadberry-log-archive-eu-west-2"  # cross-account S3
  is_organization_trail         = true    # covers ALL accounts in the org
  is_multi_region_trail         = true    # covers all regions
  include_global_service_events = true    # IAM, STS, etc.
  enable_log_file_validation    = true    # SHA-256 digest to detect tampering

  tags = { managed_by = "terraform" }
}
```

> Management events are free. Do NOT enable data events (S3 object-level, Lambda) — they add cost.

---

### Step 3 — audit account: GuardDuty delegated admin

```hcl
# Enable GuardDuty in audit account (becomes the delegated admin)
resource "aws_guardduty_detector" "audit" {
  provider = aws.audit
  enable   = true
}

# Delegate GuardDuty admin from management account to audit account
resource "aws_guardduty_organization_admin_account" "audit" {
  provider         = aws.management
  admin_account_id = var.audit_account_id
}

# Auto-enrol all existing and future org accounts into GuardDuty
resource "aws_guardduty_organization_configuration" "audit" {
  provider    = aws.audit
  detector_id = aws_guardduty_detector.audit.id
  auto_enable_organization_members = "ALL"
}
```

---

### Step 4 — audit account: Security Hub delegated admin

```hcl
# Enable Security Hub in audit account
resource "aws_securityhub_account" "audit" {
  provider = aws.audit
}

# Delegate Security Hub admin to audit account
resource "aws_securityhub_organization_admin_account" "audit" {
  provider         = aws.management
  admin_account_id = var.audit_account_id
  depends_on       = [aws_securityhub_account.audit]
}

# Enable CIS and AWS Foundational standards
resource "aws_securityhub_standards_subscription" "cis" {
  provider      = aws.audit
  standards_arn = "arn:aws:securityhub:::ruleset/cis-aws-foundations-benchmark/v/1.2.0"
  depends_on    = [aws_securityhub_account.audit]
}
```

---

### Step 5 — sandbox account: enable baseline

```hcl
# GuardDuty in sandbox (auto-enrolled in Step 3, but explicit is cleaner)
resource "aws_guardduty_detector" "sandbox" {
  provider = aws.sandbox
  enable   = true
}

# Config recorder in sandbox
resource "aws_config_configuration_recorder" "sandbox" {
  provider = aws.sandbox
  name     = "default"
  role_arn = aws_iam_role.config.arn
  recording_group { all_supported = true }
}

resource "aws_config_delivery_channel" "sandbox" {
  provider       = aws.sandbox
  name           = "default"
  s3_bucket_name = "loadberry-log-archive-eu-west-2"   # send Config snapshots to log-archive too
  depends_on     = [aws_config_configuration_recorder.sandbox]
}

resource "aws_config_configuration_recorder_status" "sandbox" {
  provider   = aws.sandbox
  name       = aws_config_configuration_recorder.sandbox.name
  is_enabled = true
  depends_on = [aws_config_delivery_channel.sandbox]
}
```

---

## Validation

### Check 1 — CloudTrail logs landing in log-archive S3

```bash
# Wait 5 minutes after apply, then check
aws s3 ls s3://loadberry-log-archive-eu-west-2/AWSLogs/ \
  --profile log-archive-admin --recursive | head -20

# Expected: folders per account ID, then date-partitioned log files
# AWSLogs/MGMT_ACCOUNT_ID/CloudTrail/eu-west-2/YYYY/MM/DD/*.json.gz
```

### Check 2 — GuardDuty findings visible in audit account

Generate a test finding (GuardDuty has a built-in test):

```bash
aws guardduty create-sample-findings \
  --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text --profile sandbox-admin) \
  --finding-types "UnauthorizedAccess:EC2/SSHBruteForce" \
  --profile sandbox-admin
```

Then verify it appears in the audit account:

```bash
aws guardduty list-findings \
  --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text --profile audit-admin) \
  --profile audit-admin
# Expected: the test finding from sandbox appears here — cross-account aggregation confirmed
```

### Check 3 — Security Hub findings visible in audit account

```bash
aws securityhub get-findings \
  --filters '{"RecordState":[{"Value":"ACTIVE","Comparison":"EQUALS"}]}' \
  --profile audit-admin \
  --query 'Findings[:3].{Title:Title,Severity:Severity.Label,Account:AwsAccountId}' \
  --output table
# Expected: findings from sandbox account appearing in audit account
```

### Check 4 — Object Lock is active on log-archive bucket

```bash
aws s3api get-object-lock-configuration \
  --bucket loadberry-log-archive-eu-west-2 \
  --profile log-archive-admin
# Expected: ObjectLockEnabled=Enabled, Mode=GOVERNANCE, Days=7
```

### Check 5 — CloudTrail log file validation

```bash
aws cloudtrail validate-logs \
  --trail-arn arn:aws:cloudtrail:eu-west-2:MGMT_ACCOUNT_ID:trail/loadberry-org-trail \
  --start-time $(date -u -v-1H +%Y-%m-%dT%H:%M:%SZ) \
  --profile management-admin
# Expected: "Results requested for ..." with no validation errors
```

---

## Validation Summary

| Check | Command location | Expected result |
|---|---|---|
| 1 — CloudTrail logs in S3 | log-archive account | Log files under `AWSLogs/` |
| 2 — GuardDuty cross-account | sandbox → audit | Test finding appears in audit |
| 3 — Security Hub cross-account | sandbox → audit | Findings from sandbox in audit |
| 4 — Object Lock active | log-archive account | GOVERNANCE mode, 7-day retention |
| 5 — Log file integrity | management account | No validation errors |

---

## Teardown (after test)

Services to disable — stops all ongoing charges after free trial:

```bash
# 1. Disable GuardDuty in sandbox (audit account auto-disables member)
aws guardduty delete-detector \
  --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text) \
  --profile sandbox-admin

# 2. Stop Config recorder in sandbox
aws configservice stop-configuration-recorder \
  --configuration-recorder-name default \
  --profile sandbox-admin

# 3. Disable Security Hub in sandbox
aws securityhub disable-security-hub --profile sandbox-admin
```

**Keep running (free or negligible cost):**
- CloudTrail org trail — management events free, provides real audit value
- log-archive S3 bucket — ~$0.01/month, keep as the permanent audit store
- Accounts themselves — no per-account charge

**Do NOT close the accounts** — AWS accounts have a 90-day closure commitment.
Disabling services is sufficient. Empty accounts cost nothing.

---

## Notes

- **GOVERNANCE vs COMPLIANCE mode** — this plan uses GOVERNANCE for POC so the bucket can be cleaned up. Switch to `COMPLIANCE` + 365-day retention for Loadberry production. Once set to COMPLIANCE, even root cannot delete objects before expiry.
- **Control Tower** — when enrolling CT for Loadberry production, it recreates this setup automatically. The manual wiring here is for learning and POC only.
- **Account creation** — log-archive and audit accounts must exist (created via `aws-org-infra`) before `aws-security-infra` can deploy anything into them.
