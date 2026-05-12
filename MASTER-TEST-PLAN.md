# Master Test Plan

Single reference for all POC tests. Check this file first to know where you are.
Detailed instructions for each test are in the linked files — this is the tracker.

---

## Overall Progress

```
[ ] Test 1 — TGW (3-account hub-and-spoke routing)
[ ] Test 2 — Security Baseline (GuardDuty + Security Hub + Config in sandbox)
[ ] Test 3 — Security Infra (log-archive + audit accounts)
[ ] Test 4 — Monitoring (logs, alarms, Discord, Grafana)
```

Mark each `[x]` as you complete it. Come back here when you lose track.

---

## Prerequisites (do once, before current TGW and sandbox tests)

### In AWS console / CLI (one-time setup)
- [ ] RAM org sharing enabled. First confirm the local management SSO profile, then run `aws ram enable-sharing-with-aws-organization --profile <management-profile>`
- [ ] OIDC roles added in `aws-org-infra/2-organisation/github_oidc.tf` for shared-services and sandbox

### aws-terraform-modules (must be tagged first)
- [ ] transit-gateway module written and tagged `v1.0.0`
- [ ] All consuming repos reference `?ref=v1.0.0` (not main branch)

---

## Test 1 — Transit Gateway

**Owner:** aws-org-infra orchestrates; aws-shared-services-infra owns the hub; aws-sandbox-infra owns the sandbox spoke
**Full plan:** this section
**Cost:** ~$0.43 for 2 hours
**Duration:** ~2 hours build + validation

### Topology
```
Management (spoke 1)    Shared-services (hub)    Sandbox (spoke 2)
10.0.0.0/16             10.1.0.0/16              10.2.0.0/16
temp VPC + EC2          TGW + RAM share          VPC + EC2
public subnet for SSM   2 public + 2 private     public subnet for SSM
destroy after test      keep permanently         keep permanently
```

This is a Transit Gateway transitive-routing test, not a VPC peering test.
Management and sandbox must reach each other through TGW even though there is no
direct peering connection between those VPCs.

### Pre-flight
- [ ] No existing VPC using 10.0.0.0/16 in management account
  ```bash
  aws ec2 describe-vpcs --query 'Vpcs[].CidrBlock' --profile <management-profile>
  ```
- [ ] RAM org sharing enabled (see prerequisites above)
- [ ] TGW RAM share uses explicit principals only: sandbox account + temporary management account
- [ ] Do not share the TGW to the whole AWS Organization

### Build sequence
- [ ] Step 1: shared-services — 2 public + 2 private subnet VPC, TGW, explicit RAM share, TGW attachment, EC2 (apply first)
- [ ] Step 2: sandbox — VPC, TGW attachment, routes to shared-services + management, EC2 (apply second)
- [ ] Step 3: management — temp VPC, TGW attachment, routes to shared-services + sandbox, EC2 in `aws-org-infra/4-management-tgw-test` (apply third)
- [ ] Step 4: verify TGW route table has all 3 CIDRs propagated

### Validation
- [ ] Test 1: `ping 10.1.x.x` from sandbox EC2 → success
- [ ] Test 2: `ping 10.2.x.x` from shared-services EC2 → success
- [ ] Test 3: `ping 10.1.x.x` from management EC2 → success
- [ ] Test 4: `ping 10.0.x.x` from shared-services EC2 → success
- [ ] Test 5: `ping 10.2.x.x` from management EC2 → success
- [ ] Test 6: `ping 10.0.x.x` from sandbox EC2 → success
```bash
# Get into EC2 via SSM (no bastion needed)
aws ssm start-session --target i-XXXXXXXXXX --profile shared-services-admin
ping 10.2.0.x
```

### Teardown
- [ ] Terminate all 3 test EC2 instances
- [ ] Destroy management VPC + TGW attachment + temp resources
- [ ] Remove the temporary management account principal from the TGW RAM share
- [ ] Keep: shared-services TGW + VPC, sandbox VPC + TGW attachment

---

## Test 2 — Security Baseline (sandbox account)

**Owner:** aws-sandbox-infra
**Full plan:** `aws-org-infra/SECURITY-INFRA-TEST-PLAN.md` (Steps 1–5 sandbox section)
**Cost:** ~$0 (30-day free trial for GuardDuty + Security Hub)
**Duration:** ~1 hour build, then leave running

### What gets enabled in sandbox
```
GuardDuty detector     ← threat detection
Security Hub           ← CIS benchmark compliance checks
Config recorder        ← resource change tracking → log-archive S3
```

### Pre-flight
- [ ] log-archive S3 bucket exists (Test 3 Step 1 must run first for Config delivery)
- [ ] GuardDuty + Security Hub can be enabled independently (no log-archive dependency)

### Build sequence
- [ ] Enable GuardDuty in sandbox
- [ ] Enable Security Hub + CIS standard in sandbox
- [ ] Enable Config recorder (standalone, delivery channel added after log-archive exists)

### Validation
- [ ] GuardDuty detector active in sandbox console
- [ ] Security Hub showing CIS benchmark findings
- [ ] Generate test GuardDuty finding:
  ```bash
  aws guardduty create-sample-findings \
    --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text) \
    --finding-types "UnauthorizedAccess:EC2/SSHBruteForce" \
    --profile sandbox-admin
  ```
- [ ] Test finding appears in sandbox GuardDuty console

### Notes
- GuardDuty delegation to audit account happens in Test 3 — findings stay local until then
- Config delivery channel to log-archive S3 added in Test 3 after bucket exists

---

## Test 3 — Security Infra (log-archive + audit accounts)

**Owner:** aws-security-infra
**Full plan:** `aws-security-infra/SECURITY-INFRA-TEST-PLAN.md`
**Cost:** ~$0.50 total
**Duration:** ~2 hours build + validation

### What gets built
```
log-archive account    S3 bucket (Object Lock GOVERNANCE mode, 7-day retention)
management account     Org-level CloudTrail → log-archive S3
audit account          GuardDuty delegated admin (aggregates from all accounts)
audit account          Security Hub delegated admin (aggregates from all accounts)
sandbox account        Config delivery channel → log-archive S3 (completes Test 2)
```

### Pre-flight
- [ ] log-archive account created in aws-org-infra (accounts.tf PR merged)
- [ ] audit account created in aws-org-infra (accounts.tf PR merged)
- [ ] CIDR.md still reserves 10.3.0.0/16 for log-archive and 10.4.0.0/16 for audit
- [ ] OIDC roles added in `aws-org-infra/2-organisation/github_oidc.tf` for log-archive and audit
- [ ] Test 2 complete (GuardDuty + Security Hub already running in sandbox)

### Build sequence
- [ ] Step 1: log-archive S3 bucket with Object Lock (GOVERNANCE, 7 days)
- [ ] Step 2: org-level CloudTrail in management → log-archive S3
- [ ] Step 3: GuardDuty delegated admin → audit account
- [ ] Step 4: Security Hub delegated admin → audit account
- [ ] Step 5: Config delivery channel in sandbox → log-archive S3

### Validation
- [ ] Check 1: CloudTrail logs landing in log-archive S3
  ```bash
  aws s3 ls s3://loadberry-log-archive-eu-west-2/AWSLogs/ --profile log-archive-admin --recursive | head -20
  ```
- [ ] Check 2: GuardDuty test finding from sandbox appears in audit account
  ```bash
  aws guardduty list-findings \
    --detector-id $(aws guardduty list-detectors --query 'DetectorIds[0]' --output text --profile audit-admin) \
    --profile audit-admin
  ```
- [ ] Check 3: Security Hub findings from sandbox visible in audit account
- [ ] Check 4: Object Lock active on log-archive bucket
- [ ] Check 5: CloudTrail log file validation passes

### Teardown (after test)
- [ ] Disable GuardDuty in sandbox (stops billing after free trial)
- [ ] Stop Config recorder in sandbox
- [ ] Disable Security Hub in sandbox
- [ ] Keep: CloudTrail, log-archive S3 bucket, accounts (no per-account charge)

---

## Test 4 — Monitoring (operational observability)

**Owner:** aws-shared-services-infra (SNS + Grafana) + aws-sandbox-infra (logs + alarms)
**Full plan:** `aws-org-infra/MONITORING.md`
**Cost:** ~$12-15/month
**Duration:** ~3 hours build + validation

### What gets built
```
Phase 1 — Passive logs
  VPC Flow Logs → S3 (sandbox)
  ALB access logs → S3 (sandbox)
  RDS logs → CloudWatch Logs (sandbox)

Phase 2 — Alerting
  SNS central topic (shared-services)
  Lambda → Discord webhook (shared-services)
  CloudWatch Alarms → SNS (sandbox)
  GuardDuty finding → EventBridge → SNS (security-infra)

Phase 3 — EKS observability
  Container Insights addon (sandbox)
  Fluent Bit DaemonSet — pod logs + metrics

Phase 4 — Grafana dashboard
  Grafana workspace (shared-services)
  CloudWatch OAM sink (org-infra)
  OAM link from sandbox → sink (sandbox)
```

### Pre-flight
- [ ] Discord #loadberry-aws-alerts channel created
- [ ] Discord webhook URL created + stored in Secrets Manager
- [ ] Test 1 complete (VPC + ALB exist in sandbox)
- [ ] Test 2 complete (GuardDuty running in sandbox for alert testing)
- [ ] EKS cluster running in sandbox (Phase 3 only)

### Build sequence
- [ ] Phase 1: VPC Flow Logs, ALB logs, RDS logs (apply to sandbox)
- [ ] Phase 2: SNS + Discord Lambda (apply to shared-services), then Alarms (apply to sandbox)
- [ ] Phase 3: Container Insights addon (apply to sandbox, requires EKS running)
- [ ] Phase 4: Grafana workspace + OAM sink/link (apply to shared-services + org-infra)

### Validation
- [ ] VPC Flow Logs appear in S3 within 10 minutes
- [ ] ALB access logs appear in S3 after first HTTP request
- [ ] RDS logs appear in CloudWatch Logs group
- [ ] Trigger test alarm → Discord notification received in #loadberry-aws-alerts
  ```bash
  # Manually set alarm to ALARM state for testing
  aws cloudwatch set-alarm-state \
    --alarm-name sandbox-alb-5xx-high \
    --state-value ALARM \
    --state-reason "Manual test" \
    --profile sandbox-admin
  ```
- [ ] Container Insights shows pod CPU/memory in CloudWatch console
- [ ] Grafana workspace accessible via SSO login
- [ ] Grafana EKS dashboard shows sandbox cluster metrics

### Teardown (optional — keep for ongoing use)
- Monitoring is designed to run permanently
- Container Insights (~$9/month) can be disabled if EKS is destroyed
- Grafana workspace free for 90 days, then $9/user/month

---

## Cost Summary — All Tests

| Test | One-time cost | Ongoing after test |
|---|---|---|
| Test 1 — TGW | ~$0.43 (2hr) | ~$72/month (TGW + attachments) |
| Test 2 — Security baseline | $0 (free trial) | ~$5-8/month after trial |
| Test 3 — Security infra | ~$0.50 | ~$1/month (S3 + CloudTrail) |
| Test 4 — Monitoring | ~$0 setup | ~$12-15/month |
| **Total ongoing** | | **~$90-95/month** |

> Destroy EKS when not actively testing — saves $72/month alone.
> TGW is the main ongoing cost (~$72/month) but is real production infrastructure.

---

## Reference Files

| File | What it covers |
|---|---|
| `ACCOUNT.md` | Account inventory, OU structure, creation workflow |
| `CIDR.md` | IP address allocations, subnet layout, TGW routing strategy |
| `MASTER-TEST-PLAN.md` | Canonical cross-repo TGW build + validation sequence |
| `aws-security-infra/SECURITY-INFRA-TEST-PLAN.md` | Full security infra build + validation |
| `MONITORING.md` | Full monitoring build + Grafana + Discord setup |
| `FINOPS.md` | Cost management plan (post-testing) |
| `FINTECH.md` | Compliance plan — PCI DSS, SOC 2, GDPR (post-testing) |
