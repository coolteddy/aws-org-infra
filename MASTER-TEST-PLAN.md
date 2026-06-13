# Master Test Plan

Single reference for all POC tests. Check this file first to know where you are.
Update checkboxes as you complete each step.

---

## POC Principle

Nothing in this environment is permanent unless explicitly marked to keep.
Cost cleanup is part of the acceptance criteria — destroy every billable resource after validation.

---

## Code Status

```
[x] aws-terraform-modules        v1.0.0 tagged — all 15 modules
[x] aws-shared-services-infra    merged + applied — VPC + TGW + RAM share live
[x] aws-sandbox-infra            merged + applied — VPC + TGW attachment + security baseline live
[x] aws-org-infra                accounts.tf (log-archive + audit) + OIDC role applied
[x] aws-org-infra                4-management-tgw-test/ — written, not yet applied
[x] aws-security-infra           both rounds applied — CloudTrail + GuardDuty + Security Hub + Config bucket policy live
```

## Deployment Progress

```
[x] Phase 0 — Accounts        log-archive + audit accounts created and applied
[x] Phase 1 — Security infra  log-archive S3 bucket + delegated admin ready
[x] Phase 2 — TGW test        all 3 accounts built, all 6 ping paths pass
[x] Phase 4 — Teardown        all billable test resources destroyed
[x] Phase 3 — Security check  aggregation + Config delivery verified
[ ] Security teardown         disable billable POC services through Terraform  ← NEXT
[ ] Phase 5 — Monitoring      logs, alarms, Discord, Grafana (deferred, build after POC)
```

### Phase 0 — COMPLETE

Applied via GitHub Actions PR flow. Resources created:
- log-archive account — Security OU
- audit account — Security OU
- github-actions-aws-security-infra OIDC gateway role (two-account target)
- deny_security_monitoring_disable SCP — modified (already existed)

**Important teardown note:** `deny_security_monitoring_disable` SCP blocks GuardDuty and Config
destroy operations. Must temporarily relax this SCP before running `terraform destroy` on
security baseline resources in sandbox. See Phase 4 teardown steps.

Mark each `[x]` as you complete it. Come back here when you lose track.

---

## Pre-flight — local AWS CLI profiles

Before running any validation commands, you need one SSO profile per account.
Terraform itself does not need these — only the manual validation CLI commands do.

```bash
aws configure sso
# SSO start URL: https://d-9c674bca0e.awsapps.com/start/
# SSO region: eu-west-2
# Run through once per account and name each profile:
```

| Profile | Account | When needed |
|---|---|---|
| `setnay-admin` | Management | ✅ Already exists |
| `setnay-sandbox` | Sandbox | ✅ Already exists |
| `setnay-log-archive` | log-archive | Needed for Phase 1 + 3 validation |
| `setnay-audit` | Audit | Needed for Phase 3 validation |

- [x] `setnay-log-archive` profile created
- [x] `setnay-audit` profile created

---

## Phase 0 — Accounts (prerequisite for everything else)

Add to `aws-org-infra/2-organisation/accounts.tf` and apply:

```hcl
resource "aws_organizations_account" "log_archive" {
  name      = "log-archive"
  email     = var.log_archive_email
  parent_id = aws_organizations_organizational_unit.security.id
  close_on_deletion = false
  lifecycle { prevent_destroy = true }
}

resource "aws_organizations_account" "audit" {
  name      = "audit"
  email     = var.audit_email
  parent_id = aws_organizations_organizational_unit.security.id
  close_on_deletion = false
  lifecycle { prevent_destroy = true }
}
```

Also add OIDC roles in `aws-org-infra/2-organisation/github_oidc.tf` for:
- `aws-security-infra` → log-archive account
- `aws-security-infra` → audit account

Checklist:
- [ ] log-archive account created and visible in AWS Organizations console
- [ ] audit account created and visible in AWS Organizations console
- [ ] OIDC roles added for aws-security-infra (log-archive + audit)
- [ ] RAM org sharing enabled: `aws ram enable-sharing-with-aws-organization --profile management-admin`

---

## Phase 1 — Security Infrastructure

**Repo:** `aws-security-infra`
**Cost:** ~$0.50 total (GuardDuty + Security Hub on 30-day free trial)
**Why first:** log-archive S3 bucket must exist before sandbox Config delivery channel can be enabled.

### What to apply — two rounds

**Round 1 — log-archive bucket first (unblocks sandbox Config delivery channel)**

```
log_archive.tf    S3 bucket + Object Lock GOVERNANCE 7-day + bucket policy
```

Checklist:
- [x] log-archive S3 bucket created with Object Lock enabled (default retention removed — Config delivery incompatible with default retention)

**Round 2 — after bucket is confirmed applied**

```
cloudtrail.tf     Org-level CloudTrail → log-archive S3 (management events free)
guardduty.tf      GuardDuty delegated admin → audit account + auto-enrol all accounts
securityhub.tf    Security Hub delegated admin → audit account + CIS standard
```

Checklist:
- [x] CloudTrail org trail active
- [x] GuardDuty delegated admin set to audit account
- [x] Security Hub delegated admin set to audit account

**Keep after POC:** CloudTrail + log-archive S3 (free / negligible cost)
**Destroy after POC:** GuardDuty + Security Hub if ongoing cost not acceptable (see Phase 4)

---

## Phase 2 — TGW Test

**Cost:** ~$0.43 for 2 hours
**Duration:** ~2 hours build + validation

### Topology

```
Management (spoke 1 — temporary)    Shared-services (hub)    Sandbox (spoke 2 — permanent)
10.0.0.0/16                         10.1.0.0/16              10.2.0.0/16
1 public subnet                     2 public + 2 private     2 public + 2 private
EC2 t3.nano + EIP                   EC2 t3.nano + EIP        EC2 t3.nano + EIP
TGW attachment                      TGW + RAM share          TGW attachment
DESTROY after test                  keep VPC + TGW           keep VPC
```

TGW transitive routing is the key proof: sandbox ↔ management must reach each other
through TGW even though there is no direct peering between those two VPCs.

### VPC allocations (do not change)

| Account | CIDR | Subnets |
|---|---|---|
| Management (temp) | 10.0.0.0/16 | 1 public eu-west-2a — destroy after test |
| Shared-services | 10.1.0.0/16 | 2 public + 2 private eu-west-2a/b — keep |
| Sandbox | 10.2.0.0/16 | 2 public + 2 private eu-west-2a/b — keep |

### Pre-flight

- [x] No existing VPC using 10.0.0.0/16 in management account (only default VPC 172.31.0.0/16)
- [x] RAM org sharing enabled
- [x] TGW RAM share uses explicit principals only: sandbox + management
- [x] SCP check passed

### Build sequence — all done on the same test day

**Step 1 — VPC only, all 3 repos (local apply)**

Verify CIDRs before wiring TGW. Comment out TGW resources, apply VPCs only.

```bash
# shared-services — comment out tgw.tf content, apply vpc.tf only
cd aws-shared-services-infra
export AWS_PROFILE=setnay-admin
terraform apply   # creates VPC 10.1.0.0/16 only

# sandbox — comment out tgw_attachment.tf content, apply vpc.tf only
cd aws-sandbox-infra
terraform apply   # creates VPC 10.2.0.0/16 only

# management — comment out tgw_attachment.tf + ec2_tgw_test.tf, apply vpc.tf only
cd aws-org-infra/4-management-tgw-test
terraform apply   # creates VPC 10.0.0.0/16 only
```

- [x] VPC 10.1.0.0/16 created in shared-services (vpc-03a2d1e29da6f3b9f)
- [x] VPC 10.2.0.0/16 created in sandbox (vpc-04b312cfa57f490bb)
- [x] VPC 10.0.0.0/16 created in management (vpc-02eeacfbd2799c896)

**Step 2 — TGW hub (shared-services via GitHub Actions)**

Uncomment `tgw.tf`. Set variables:
- `create_tgw_test_instance = true`
- `tgw_test_account_ids = ["<management-account-id>"]`

Push/merge to main → GitHub Actions apply runs.

```bash
terraform output transit_gateway_id   # capture this — needed for Steps 3 and 4
```

- [x] TGW created in shared-services (tgw-0ca4741646065bbc8)
- [x] RAM share created with sandbox + management as explicit principals
- [x] `transit_gateway_id` captured: tgw-0ca4741646065bbc8

**Step 3 — Sandbox TGW attachment + security baseline (GitHub Actions)**

Uncomment `tgw_attachment.tf`. Set variables:
- `tgw_id = "<from Step 2 output>"`
- `create_tgw_test_instance = true`
- `log_archive_bucket = "loadberry-log-archive-eu-west-2"`

Update `TGW_ID` GitHub Actions variable. Push/merge to main → workflow runs.

- [x] Sandbox TGW attachment created (tgw-attach-07667827ee4501675)
- [x] Security baseline applied (Security Hub + Config recorder — GuardDuty org-managed)
- [x] Routes to 10.1.0.0/16 and 10.0.0.0/16 in sandbox route tables

**Step 4 — Management full spoke (local)**

Uncomment everything in `4-management-tgw-test/`. Update `terraform.tfvars`:
- `tgw_id = "<from Step 2 output>"`
- `create_tgw_test_instance = true`

```bash
cd aws-org-infra/4-management-tgw-test
terraform apply   # VPC + TGW attachment + routes + EC2 — all in one apply
```

- [x] Management TGW attachment created (tgw-attach-0dc9f05b4d0373d38)
- [x] Routes to 10.1.0.0/16 and 10.2.0.0/16 in management route tables
- [x] Management test EC2 running (i-04bd03fe532b1db66, 10.0.0.214)

**Step 5 — Verify TGW route table has all 3 CIDRs propagated**

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id tgw-rtb-XXXXXXXXXX \
  --filters Name=type,Values=propagated \
  --profile setnay-admin
```

- [x] 10.0.0.0/16, 10.1.0.0/16, 10.2.0.0/16 all showing as propagated (tgw-rtb-055841647aabdb356)

### Validation — all 6 ping paths must pass

```bash
# Get into EC2 via SSM — no bastion needed
aws ssm start-session --target i-XXXXXXXXXXXXXXXXX --profile <account>-admin
```

| Test | From | To | Command | Expected |
|---|---|---|---|---|
| 1 | Shared-services EC2 | Sandbox EC2 `10.2.0.81` | `ping 10.2.0.81` | ✅ 0% loss |
| 2 | Sandbox EC2 | Shared-services EC2 `10.1.0.62` | `ping 10.1.0.62` | ✅ 0% loss |
| 3 | Shared-services EC2 | Management EC2 `10.0.0.214` | `ping 10.0.0.214` | ✅ 0% loss |
| 4 | Management EC2 | Shared-services EC2 `10.1.0.62` | `ping 10.1.0.62` | ✅ 0% loss |
| 5 | Management EC2 | Sandbox EC2 `10.2.0.81` | `ping 10.2.0.81` | ✅ 0% loss TRANSITIVE |
| 6 | Sandbox EC2 | Management EC2 `10.0.0.214` | `ping 10.0.0.214` | ✅ 0% loss TRANSITIVE |

Tests 5 and 6 prove transitive routing through TGW. VPC peering cannot do this.

---

## Phase 3 — Security Validation

Run after Phase 2. Security infra was set up in Phase 1 — this phase verifies it works.

### Security baseline in sandbox

Before enabling, check Workloads OU SCPs do not block GuardDuty or Config operations.
If an SCP blocks them, relax it manually in the console, enable the services, then restore.

- [x] Apply `aws-sandbox-infra` security baseline (already in `security_baseline.tf`)
  - GuardDuty enabled through organization management
  - Security Hub + CIS standard enabled
  - Config recorder + delivery channel → log-archive S3 bucket

### Validation checks

- [x] Check 1: CloudTrail logs landing in log-archive S3
  - 920 CloudTrail objects observed in the first 1,000 listed objects
  ```bash
  aws s3 ls s3://loadberry-log-archive-eu-west-2/AWSLogs/ \
    --profile log-archive-admin --recursive | head -20
  ```

- [x] Check 2: Generate test GuardDuty finding in sandbox
  ```bash
  aws guardduty create-sample-findings \
    --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text --profile sandbox-admin) \
    --finding-types "UnauthorizedAccess:EC2/SSHBruteForce" \
    --profile sandbox-admin
  ```

- [x] Check 3: Verify finding appears in audit account (cross-account aggregation)
  - Sample `UnauthorizedAccess:EC2/SSHBruteForce` finding visible in audit CLI and console
  - Historical `CloudTrailLoggingDisabled` finding investigated and archived
  - Current organization trail confirmed logging with recent delivery and no error
  ```bash
  aws guardduty list-findings \
    --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text --profile audit-admin) \
    --profile audit-admin
  ```

- [x] Check 4: Security Hub findings from sandbox visible in audit account
  - Initial gap: audit used `LOCAL` configuration with `AutoEnable=false` and had zero members
  - Added `aws_securityhub_member.sandbox` through `aws-security-infra`
  - Sandbox member status verified as `Enabled`
  - Sandbox GuardDuty and compliance findings visible in audit
- [x] Check 5: Config snapshots landing in log-archive S3
  - 80 Config objects observed in the first 1,000 listed objects
  ```bash
  aws s3 ls s3://loadberry-log-archive-eu-west-2/AWSLogs/ \
    --profile setnay-log-archive --recursive | grep Config | head -10
  ```
- [x] Check 6: Object Lock active on log-archive bucket
  - `ObjectLockEnabled=Enabled`
  - Default retention is absent; AWS Config does not support delivery when default retention is enabled
  ```bash
  aws s3api get-object-lock-configuration \
    --bucket loadberry-log-archive-eu-west-2 \
    --profile log-archive-admin
  ```

---

## Phase 4 — Teardown

Destroy in this exact order to avoid dependency errors.

### TGW teardown order

```
1. ✅ Set create_tgw_test_instance = false in all 3 repos + apply → all EC2 destroyed
2. ✅ Management: commented out all resources + applied → VPC + TGW attachment + everything destroyed
3. ✅ Sandbox: commented out tgw_attachment.tf + applied → TGW attachment + routes destroyed, VPC kept
4. ✅ Shared-services: commented out tgw.tf + applied → TGW + RAM share + routes destroyed, VPC kept
```

### VPC retention rules

| VPC | Action | Reason |
|---|---|---|
| Management 10.0.0.0/16 | **Always destroy** | Temporary test VPC, no future use |
| Shared-services 10.1.0.0/16 | **Keep** | Permanent hub — future ECR, Route53, services |
| Sandbox 10.2.0.0/16 | **Keep** | Permanent workload VPC — Priority 3 needs it |

### Security baseline teardown (if ongoing cost not acceptable)

Security validation is complete. GuardDuty and Security Hub trials are ending, and
AWS Config is usage-priced. Plan this teardown before executing it:

1. Inventory GuardDuty organization members to identify auto-enabled detectors
2. Temporarily remove only GuardDuty + Config deny actions from `DenySecurityMonitoringDisable`
3. In `aws-sandbox-infra`, remove Config recorder/delivery resources and sandbox Security Hub
4. In `aws-security-infra`, remove Security Hub member, standards, delegated admin, and audit account enablement
5. Remove GuardDuty organization configuration, delegated admin, audit detector, and auto-enabled member detectors
6. Restore `DenySecurityMonitoringDisable`
7. Verify GuardDuty, Security Hub, and Config no longer produce ongoing charges
8. Keep CloudTrail + log-archive S3 (free / negligible cost and real audit value)

### Immediate remediation after security teardown

- [ ] HIGH `EC2.2`: remove all rules from the sandbox VPC default security group
- [ ] MEDIUM `EC2.15`: disable automatic public IPv4 assignment on both sandbox public subnets
- [ ] Implement both fixes in `aws-terraform-modules`, tag a new version, and update sandbox

---

## Phase 5 — Monitoring (deferred)

Build after POC tests pass. Not part of the current test cycle.

**Owner:** aws-shared-services-infra (SNS + Grafana) + aws-sandbox-infra (logs + alarms)
**Full plan:** `aws-org-infra/MONITORING.md`
**Cost:** ~$12-15/month ongoing

What gets built:
```
VPC Flow Logs + ALB access logs + RDS logs → S3
SNS central topic → Lambda → Discord webhook
CloudWatch Alarms → SNS
GuardDuty finding → EventBridge → SNS
Container Insights + Fluent Bit (EKS only)
Grafana workspace + CloudWatch OAM sink/link
```

---

## Cost Summary

| Phase | One-time | Ongoing after test |
|---|---|---|
| Phase 1 — Security infra | ~$0.50 | ~$1/month (S3 + CloudTrail only if GuardDuty/SHub disabled) |
| Phase 2 — TGW test | ~$0.43 (2hr) | $0 after teardown |
| Phase 3 — Security baseline | $0 (free trial) | ~$5-8/month if kept |
| Phase 5 — Monitoring | ~$0 setup | ~$12-15/month |

> Full POC test cost: under $1 if run within 30-day free trial window and TGW torn down after.

---

## Reference Files

| File | What it covers |
|---|---|
| `ACCOUNT.md` | Account inventory, OU structure, creation workflow |
| `CIDR.md` | IP address allocations, subnet layout, TGW routing strategy |
| `MASTER-TEST-PLAN.md` | This file — canonical cross-repo execution plan |
| `aws-security-infra/SECURITY-INFRA-TEST-PLAN.md` | Full security infra build + validation detail |
| `MONITORING.md` | Full monitoring build + Grafana + Discord setup |
| `FINOPS.md` | Cost management plan (post-testing) |
| `FINTECH.md` | Compliance plan — PCI DSS, SOC 2, GDPR (post-testing) |
