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
[x] aws-shared-services-infra    feat/tgw-hub — VPC + TGW + RAM share + workflows (PR open)
[x] aws-sandbox-infra            VPC + TGW attachment + EC2 test + security baseline + workflows
[x] aws-org-infra                accounts.tf (log-archive + audit) + OIDC role applied
[x] aws-org-infra                4-management-tgw-test/ — written, not yet applied
[ ] aws-security-infra           no Terraform files yet
```

## Deployment Progress

```
[x] Phase 0 — Accounts        log-archive + audit accounts created and applied
[x] Phase 1 — Security infra  log-archive S3 bucket + delegated admin ready
[ ] Phase 2 — TGW test        all 3 accounts built, all 6 ping paths pass
[ ] Phase 3 — Security check  aggregation + Config delivery verified
[ ] Phase 4 — Teardown        all billable test resources destroyed
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

- [ ] `setnay-log-archive` profile created
- [ ] `setnay-audit` profile created

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
- [ ] log-archive S3 bucket created with Object Lock GOVERNANCE mode

**Round 2 — after bucket is confirmed applied**

```
cloudtrail.tf     Org-level CloudTrail → log-archive S3 (management events free)
guardduty.tf      GuardDuty delegated admin → audit account + auto-enrol all accounts
securityhub.tf    Security Hub delegated admin → audit account + CIS standard
```

Checklist:
- [ ] CloudTrail org trail active (check: CloudTrail console → Trails)
- [ ] GuardDuty delegated admin set to audit account
- [ ] Security Hub delegated admin set to audit account

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

- [ ] No existing VPC using 10.0.0.0/16 in management account
  ```bash
  aws ec2 describe-vpcs --query 'Vpcs[].CidrBlock' --profile management-admin
  ```
- [ ] RAM org sharing enabled (Phase 0 prerequisite)
- [ ] TGW RAM share will use explicit principals only: sandbox + temporary management
- [ ] SCP check: verify Workloads OU SCPs do not block TGW attachment creation in sandbox

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

- [ ] VPC 10.1.0.0/16 created in shared-services
- [ ] VPC 10.2.0.0/16 created in sandbox
- [ ] VPC 10.0.0.0/16 created in management (no CIDR conflict confirmed)

**Step 2 — TGW hub (shared-services via GitHub Actions)**

Uncomment `tgw.tf`. Set variables:
- `create_tgw_test_instance = true`
- `tgw_test_account_ids = ["<management-account-id>"]`

Push/merge to main → GitHub Actions apply runs.

```bash
terraform output transit_gateway_id   # capture this — needed for Steps 3 and 4
```

- [ ] TGW created in shared-services
- [ ] RAM share created with sandbox + management as explicit principals
- [ ] `transit_gateway_id` output captured

**Step 3 — Sandbox TGW attachment + security baseline (GitHub Actions)**

Uncomment `tgw_attachment.tf`. Set variables:
- `tgw_id = "<from Step 2 output>"`
- `create_tgw_test_instance = true`
- `log_archive_bucket = "loadberry-log-archive-eu-west-2"`

Update `TGW_ID` GitHub Actions variable. Push/merge to main → workflow runs.

- [ ] Sandbox TGW attachment created
- [ ] Security baseline applied (GuardDuty, Security Hub, Config recorder)
- [ ] Routes to 10.1.0.0/16 and 10.0.0.0/16 in sandbox route tables

**Step 4 — Management full spoke (local)**

Uncomment everything in `4-management-tgw-test/`. Update `terraform.tfvars`:
- `tgw_id = "<from Step 2 output>"`
- `create_tgw_test_instance = true`

```bash
cd aws-org-infra/4-management-tgw-test
terraform apply   # VPC + TGW attachment + routes + EC2 — all in one apply
```

- [ ] Management TGW attachment created
- [ ] Routes to 10.1.0.0/16 and 10.2.0.0/16 in management route tables
- [ ] Management test EC2 running

**Step 5 — Verify TGW route table has all 3 CIDRs propagated**

```bash
aws ec2 search-transit-gateway-routes \
  --transit-gateway-route-table-id tgw-rtb-XXXXXXXXXX \
  --filters Name=type,Values=propagated \
  --profile setnay-admin
```

- [ ] 10.0.0.0/16, 10.1.0.0/16, 10.2.0.0/16 all showing as propagated

### Validation — all 6 ping paths must pass

```bash
# Get into EC2 via SSM — no bastion needed
aws ssm start-session --target i-XXXXXXXXXXXXXXXXX --profile <account>-admin
```

| Test | From | To | Command | Expected |
|---|---|---|---|---|
| 1 | Sandbox EC2 | Shared-services EC2 | `ping 10.1.x.x` | ✅ |
| 2 | Shared-services EC2 | Sandbox EC2 | `ping 10.2.x.x` | ✅ |
| 3 | Management EC2 | Shared-services EC2 | `ping 10.1.x.x` | ✅ |
| 4 | Shared-services EC2 | Management EC2 | `ping 10.0.x.x` | ✅ |
| 5 | Management EC2 | Sandbox EC2 | `ping 10.2.x.x` | ✅ |
| 6 | Sandbox EC2 | Management EC2 | `ping 10.0.x.x` | ✅ |

Tests 5 and 6 prove transitive routing through TGW. VPC peering cannot do this.

---

## Phase 3 — Security Validation

Run after Phase 2. Security infra was set up in Phase 1 — this phase verifies it works.

### Security baseline in sandbox

Before enabling, check Workloads OU SCPs do not block GuardDuty or Config operations.
If an SCP blocks them, relax it manually in the console, enable the services, then restore.

- [ ] Apply `aws-sandbox-infra` security baseline (already in `security_baseline.tf`)
  - GuardDuty detector enabled
  - Security Hub + CIS standard enabled
  - Config recorder + delivery channel → log-archive S3 bucket

### Validation checks

- [ ] Check 1: CloudTrail logs landing in log-archive S3
  ```bash
  aws s3 ls s3://loadberry-log-archive-eu-west-2/AWSLogs/ \
    --profile log-archive-admin --recursive | head -20
  ```

- [ ] Check 2: Generate test GuardDuty finding in sandbox
  ```bash
  aws guardduty create-sample-findings \
    --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text --profile sandbox-admin) \
    --finding-types "UnauthorizedAccess:EC2/SSHBruteForce" \
    --profile sandbox-admin
  ```

- [ ] Check 3: Verify finding appears in audit account (cross-account aggregation)
  ```bash
  aws guardduty list-findings \
    --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text --profile audit-admin) \
    --profile audit-admin
  ```

- [ ] Check 4: Security Hub findings from sandbox visible in audit account
- [ ] Check 5: Config snapshots landing in log-archive S3
- [ ] Check 6: Object Lock active on log-archive bucket
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
1. Set create_tgw_test_instance = false in shared-services + apply  → destroys shared-services EC2
   Set create_tgw_test_instance = false in sandbox + apply          → destroys sandbox EC2

2. Destroy aws-org-infra/4-management-tgw-test/
   → removes management EC2 + EIP + routes + TGW attachment + VPC

3. Set tgw_test_account_ids = [] in shared-services + apply
   → removes management from RAM share + removes management route

4. Destroy sandbox TGW attachment + routes (target or full destroy)
   → sandbox VPC STAYS — keep for future workloads

5. Destroy shared-services TGW resources
   → TGW, RAM share, TGW attachment, TGW routes destroyed
   → shared-services VPC STAYS — keep as permanent hub
```

### VPC retention rules

| VPC | Action | Reason |
|---|---|---|
| Management 10.0.0.0/16 | **Always destroy** | Temporary test VPC, no future use |
| Shared-services 10.1.0.0/16 | **Keep** | Permanent hub — future ECR, Route53, services |
| Sandbox 10.2.0.0/16 | **Keep** | Permanent workload VPC — Priority 3 needs it |

### Security baseline teardown (if ongoing cost not acceptable)

GuardDuty and Config have small ongoing costs after the 30-day free trial.
If you want to stop them:

1. Check Workloads OU SCPs — some deny GuardDuty/Config destroy operations
2. Temporarily relax the SCP in the console if needed
3. Run terraform destroy on security_baseline.tf resources in sandbox
4. Restore the SCP
5. Keep: CloudTrail + log-archive S3 (free / ~$0.01/month — real audit value)

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
