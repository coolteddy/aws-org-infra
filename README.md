# aws-org-infra
## AWS Organisation Foundation - Multi-Tenant SaaS Landing Zone

> **Version:** 1.0
> **Status:** Active
> **Owner:** coolteddy

---

## What This Repository Is

This repository contains the Terraform code for the **AWS organisation foundation**.
It provisions and manages the top-level infrastructure that all tenants and products
share - the landing zone, account structure, security guardrails, and account vending pipeline.

**This repo has no knowledge of any specific product or tenant.**
Products and tenants are defined in separate repositories that consume accounts
vended by this repo.

---

## What This Repo Does NOT Contain

```
❌ Application infrastructure (VPC, EC2, ECS, RDS)
❌ Product-specific configuration
❌ Tenant workloads
❌ Terraform modules (separate repo: aws-terraform-modules)
```

---

## Repository Structure

```
aws-org-infra/
│
├── CLAUDE.md                        ← session context (gitignored)
├── README.md                        ← this file
├── MASTER-TEST-PLAN.md              ← canonical cross-repo POC execution plan
├── ACCOUNT.md                       ← account inventory and creation workflow
├── CIDR.md                          ← IP address allocations per account
├── MONITORING.md                    ← monitoring plan (post-POC)
├── FINOPS.md                        ← cost management plan (post-POC)
├── FINTECH.md                       ← compliance plan (post-POC)
├── .gitignore
│
├── 1-bootstrap/                     ← run ONCE locally, never again
│   ├── main.tf                      (S3 state bucket + DynamoDB lock table)
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
├── 2-organisation/                  ← org structure, accounts, SCPs, SSO, OIDC
│   ├── README.md
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf
│   ├── organizations.tf             (OUs)
│   ├── accounts.tf                  (AWS accounts — one block per account)
│   ├── scp_global.tf                (org-wide SCPs)
│   ├── scp_workloads.tf             (workloads OU SCPs)
│   ├── scp_prod.tf                  (prod account SCPs)
│   ├── config_rules.tf              (org Config rules)
│   ├── identity_center.tf           (SSO permission sets)
│   ├── github_oidc.tf               (GitHub Actions OIDC gateway roles — all repos)
│   └── ram.tf                       (RAM org sharing enablement)
│
├── 3-aft/                           ← account vending pipeline (code only — never applied in POC)
│   ├── README.md
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf
│   ├── account-requests/
│   │   ├── log-archive.tf
│   │   ├── audit.tf
│   │   └── shared-services.tf
│   └── account-customizations/
│       └── global/
│           ├── guardduty.tf
│           ├── security-hub.tf
│           └── baseline-iam.tf
│
├── 4-management-tgw-test/           ← temporary management TGW spoke (apply on test day only)
│   ├── versions.tf
│   ├── providers.tf
│   ├── backend.tf
│   ├── variables.tf
│   ├── vpc.tf                       (10.0.0.0/16 — 1 public subnet)
│   ├── tgw_attachment.tf            (attachment + routes to shared-services + sandbox)
│   ├── ec2_tgw_test.tf              (t3.nano — destroy after test)
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
└── .github/
    └── workflows/
        ├── 2-org-plan.yml           (PR → terraform plan)
        ├── 2-org-apply.yml          (merge to main → apply with environment gate)
        ├── 3-aft-plan.yml
        └── 3-aft-apply.yml
```

---

## The Four Layers - Mental Model

### Layer 1 - Management Account

The **"landlord" account**. Owns the Organisation. No workloads ever run here.

```
Runs: Organizations, Control Tower, IAM Identity Center, AFT, Billing
Rule: NEVER deploy application workloads here
```

### Layer 2 - Organisational Units (OUs)

Folders that group accounts. SCPs on an OU apply to ALL accounts inside it.

```
OU      = a department
Account = a team within that department

SCP inheritance flows DOWN only:
Root → OU → Child OU → Account
You can only tighten restrictions, never loosen
```

### Layer 3 - Service Control Policies (SCPs)

Set the **maximum permissions ceiling** in an account. IAM grants within that ceiling.

```
SCP does NOT grant permissions
SCP sets the ceiling - IAM grants within that ceiling

Example:
  SCP:    DENY all regions except eu-west-2
  IAM:    ALLOW EC2 full access
  Result: EC2 only works in eu-west-2
```

### Layer 4 - Member Accounts

Where actual work happens. Completely isolated by default.

```
One account per tenant per environment
├── Blast radius contained per account
├── Cost tracked per tenant
├── Security incidents isolated
└── Dev cannot touch prod - physically impossible
```

---

## Organisation Structure

```
ROOT (Management Account)
│
├── Security OU
│   ├── log-archive                ← immutable audit logs (S3 Object Lock)
│   └── audit                      ← GuardDuty + Security Hub hub
│
├── Shared OU
│   └── shared-services            ← TGW hub, ECR, Route 53
│
└── Workloads OU
    └── Tenant-A OU
        └── sandbox                ← POC workload account
```

Current accounts applied: management, shared-services, sandbox, log-archive, audit.
Future accounts (Loadberry production): per-tenant dev/staging/prod via AFT.

---

## Layer Documentation

| Layer | README | What it covers |
|-------|--------|---------------|
| Bootstrap | [1-bootstrap/README.md](1-bootstrap/README.md) | One-time setup, S3 + DynamoDB, commands |
| Organisation | [2-organisation/README.md](2-organisation/README.md) | SCPs, Config rules, SSO, OIDC, naming, account creation patterns |
| AFT | [3-aft/README.md](3-aft/README.md) | Account vending, customisations, adding tenants |
| Accounts | [ACCOUNT.md](ACCOUNT.md) | Account inventory, purposes, future plans, creation workflow |

---

## Adding a New Tenant Account

Accounts are managed via `accounts.tf` in `2-organisation/`. No AFT required.
Three patterns are available - see [2-organisation/README.md](2-organisation/README.md) for full details.

**Pattern 1 (recommended) - Terraform driven:**
```
1. Add a resource block to 2-organisation/accounts.tf
2. Open a PR - GitHub Actions runs terraform plan
3. Review the plan (correct OU, tags, email?)
4. Merge - org-production approval gate triggers
5. Approve in GitHub - account is created (~2 minutes)
6. Login via SSO: aws sso login --profile tenant-a-dev
```

**Pattern 2** - AWS Service Catalog AVM (self-service portal, no git required)

**Pattern 3** - AWS CLI + terraform import (fastest, then bring under management)

---

## Cross-Repo Deployment Model

`aws-org-infra` owns organisation-level deployment prerequisites for the other
infrastructure repos.

Deployment flow:

```
GitHub Actions in a downstream repo
  -> assumes a repo-specific gateway role in the management account
  -> assumes the target account access role
  -> Terraform manages resources in that target account
```

Current downstream targets:

| Repo | Target account | Purpose |
|------|----------------|---------|
| `aws-shared-services-infra` | shared-services | TGW hub, ECR, Route 53 |
| `aws-sandbox-infra` | sandbox | POC workload infrastructure + security baseline |
| `aws-security-infra` | log-archive + audit | Log archive bucket, CloudTrail, GuardDuty, Security Hub |

Account IDs, role ARNs, and other environment-specific values are configured in
GitHub Actions variables or secrets. They are not committed to this repository.

AWS RAM organization sharing is enabled here so RAM can work with AWS
Organizations. This does not create resource shares or grant access by itself.
Actual resource shares, such as Transit Gateway sharing, are created only in the
account and repo that owns the resource.

---

## Decisions Log

| Decision | Value | Status |
|----------|-------|--------|
| IaC tool | Terraform | ✅ Confirmed |
| Org setup | AWS Control Tower | ✅ Confirmed |
| Account vending | AFT (git-driven) | ✅ Confirmed |
| Human access | IAM Identity Center - SSO only | ✅ Confirmed |
| CI/CD auth | GitHub OIDC - no static keys | ✅ Confirmed |
| CT home region | `eu-west-2` | ✅ Confirmed |
| State backend | S3 + DynamoDB in management account | ✅ Confirmed |
| Bootstrap method | Temp IAM user → delete after SSO configured | ✅ Confirmed |
| Repo naming | `aws-org-infra` (generic, public safe) | ✅ Confirmed |
| Modules repo | Separate - `aws-terraform-modules` | ✅ Confirmed |
| Product repos | Separate per product | ✅ Confirmed |
| POC approach | Option D - apply bootstrap + org; AFT code-only (no apply) | ✅ Confirmed |
| Control Tower | Not enrolled for POC - deferred to production | ✅ Confirmed |
| AFT in POC | Written as commented educational code, never applied | ✅ Confirmed |

---

## Related Repositories

| Repo | Purpose |
|------|---------|
| `aws-org-infra` | This repo — organisation foundation, accounts, OIDC gateway roles |
| `aws-terraform-modules` | Reusable Terraform modules — versioned via git tags |
| `aws-shared-services-infra` | Shared platform — TGW hub, ECR, Route 53 |
| `aws-sandbox-infra` | POC workload account — VPC, TGW spoke, security baseline |
| `aws-security-infra` | Security accounts — log-archive + audit |

---

*This is a living document. Update the Decisions Log as choices are confirmed.*
