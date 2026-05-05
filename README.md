# aws-org-infra
## AWS Organisation Foundation — Multi-Tenant SaaS Landing Zone

> **Version:** 1.0
> **Status:** Active
> **Owner:** coolteddy

---

## What This Repository Is

This repository contains the Terraform code for the **AWS organisation foundation**.
It provisions and manages the top-level infrastructure that all tenants and products
share — the landing zone, account structure, security guardrails, and account vending pipeline.

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
├── CLAUDE.md                        ← Claude Code instructions (auto-loaded)
├── README.md                        ← this file — high-level overview
├── .gitignore
│
├── 1-bootstrap/                     ← run ONCE locally, never again
│   ├── README.md                    ← setup instructions
│   ├── main.tf                      (S3 state bucket + DynamoDB)
│   ├── variables.tf
│   ├── outputs.tf
│   └── terraform.tfvars.example
│
├── 2-organisation/                  ← org structure, SCPs, SSO, OIDC
│   ├── README.md                    ← full layer documentation
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf
│   ├── organizations.tf             (OUs)
│   ├── scp_global.tf                (org-wide SCPs)
│   ├── scp_workloads.tf             (workloads OU SCPs)
│   ├── scp_prod.tf                  (prod account SCPs)
│   ├── config_rules.tf              (org Config rules)
│   ├── identity_center.tf           (SSO permission sets)
│   └── github_oidc.tf               (GitHub Actions OIDC)
│
├── 3-aft/                           ← account vending pipeline (code only in POC)
│   ├── README.md                    ← AFT documentation
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── backend.tf
│   ├── account-requests/            ← one file = one AWS account
│   │   ├── README.md                ← how to add a new account
│   │   ├── log-archive.tf
│   │   ├── audit.tf
│   │   └── shared-services.tf
│   └── account-customizations/
│       └── global/                  ← runs in every vended account
│           ├── README.md
│           ├── guardduty.tf
│           ├── security-hub.tf
│           └── baseline-iam.tf
│
└── .github/
    └── workflows/
        ├── 2-org-plan.yml           (PR → terraform plan)
        ├── 2-org-apply.yml          (merge to main → apply)
        ├── 3-aft-plan.yml
        └── 3-aft-apply.yml
```

---

## The Four Layers — Mental Model

### Layer 1 — Management Account

The **"landlord" account**. Owns the Organisation. No workloads ever run here.

```
Runs: Organizations, Control Tower, IAM Identity Center, AFT, Billing
Rule: NEVER deploy application workloads here
```

### Layer 2 — Organisational Units (OUs)

Folders that group accounts. SCPs on an OU apply to ALL accounts inside it.

```
OU      = a department
Account = a team within that department

SCP inheritance flows DOWN only:
Root → OU → Child OU → Account
You can only tighten restrictions, never loosen
```

### Layer 3 — Service Control Policies (SCPs)

Set the **maximum permissions ceiling** in an account. IAM grants within that ceiling.

```
SCP does NOT grant permissions
SCP sets the ceiling — IAM grants within that ceiling

Example:
  SCP:    DENY all regions except eu-west-2
  IAM:    ALLOW EC2 full access
  Result: EC2 only works in eu-west-2
```

### Layer 4 — Member Accounts

Where actual work happens. Completely isolated by default.

```
One account per tenant per environment
├── Blast radius contained per account
├── Cost tracked per tenant
├── Security incidents isolated
└── Dev cannot touch prod — physically impossible
```

---

## Organisation Structure

```
ROOT (Management Account)
│
├── Security OU                    ← Control Tower managed
│   ├── log-archive                (immutable audit logs)
│   └── audit                      (GuardDuty, Security Hub)
│
├── Shared OU
│   └── shared-services            (ECR, Route 53, SES)
│
└── Workloads OU
    ├── Tenant-A OU                ← first tenant
    │   ├── tenant-a-dev
    │   ├── tenant-a-staging
    │   └── tenant-a-prod
    │
    └── Tenant-B OU                ← future tenant
        ├── tenant-b-dev
        └── tenant-b-prod
```

---

## Layer Documentation

| Layer | README | What it covers |
|-------|--------|---------------|
| Bootstrap | [1-bootstrap/README.md](1-bootstrap/README.md) | One-time setup, S3 + DynamoDB, commands |
| Organisation | [2-organisation/README.md](2-organisation/README.md) | SCPs, Config rules, SSO, OIDC, naming |
| AFT | [3-aft/README.md](3-aft/README.md) | Account vending, customisations, adding tenants |

---

## Decisions Log

| Decision | Value | Status |
|----------|-------|--------|
| IaC tool | Terraform | ✅ Confirmed |
| Org setup | AWS Control Tower | ✅ Confirmed |
| Account vending | AFT (git-driven) | ✅ Confirmed |
| Human access | IAM Identity Center — SSO only | ✅ Confirmed |
| CI/CD auth | GitHub OIDC — no static keys | ✅ Confirmed |
| CT home region | `eu-west-2` | ✅ Confirmed |
| State backend | S3 + DynamoDB in management account | ✅ Confirmed |
| Bootstrap method | Temp IAM user → delete after SSO configured | ✅ Confirmed |
| Repo naming | `aws-org-infra` (generic, public safe) | ✅ Confirmed |
| Modules repo | Separate — `aws-terraform-modules` | ✅ Confirmed |
| Product repos | Separate per product | ✅ Confirmed |
| POC approach | Option D — apply bootstrap + org; AFT code-only (no apply) | ✅ Confirmed |
| Control Tower | Not enrolled for POC — deferred to production | ✅ Confirmed |
| AFT in POC | Written as commented educational code, never applied | ✅ Confirmed |

---

## Related Repositories

| Repo | Purpose |
|------|---------|
| `aws-org-infra` | This repo — organisation foundation |
| `aws-terraform-modules` | Reusable Terraform modules (versioned) |
| `{product}-infra` | Per-product tenant infrastructure |

---

*This is a living document. Update the Decisions Log as choices are confirmed.*
