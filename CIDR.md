# CIDR Management

All IP address allocations for this AWS organisation.
Update this file before provisioning any new VPC or account.
Transit Gateway requires non-overlapping CIDRs — a conflict here breaks routing for everyone.

---

## Master IP Space

```
10.0.0.0/8   ← entire org (16 million IPs, 256 × /16 blocks)
```

All VPCs in this org use the `10.0.0.0/8` RFC 1918 range.
Each account gets exactly one `/16` block (65,534 usable IPs — more than enough per account).

---

## Account Allocations

### Foundation accounts (permanent)

| CIDR | Account | Purpose |
|---|---|---|
| `10.0.0.0/16` | Management | Org governance only — TGW test VPC (temporary, destroy after test) |
| `10.1.0.0/16` | shared-services | TGW hub, ECR, Route 53, Secrets Manager |
| `10.2.0.0/16` | sandbox | POC workloads, EKS, ALB/NLB |

### Reserved — future foundation accounts

| CIDR | Reserved for |
|---|---|
| `10.3.0.0/16` | log-archive (Security OU — created when Control Tower enrolled) |
| `10.4.0.0/16` | audit (Security OU — created when Control Tower enrolled) |
| `10.5.0.0/16` | networking (optional — dedicated TGW account at scale) |
| `10.6.0.0/16` – `10.9.0.0/16` | Reserved — do not use |

### Tenant accounts (one /16 per environment per tenant)

Pattern: `10.{10 + (N × 10) + env_offset}.0.0/16`
- N = tenant number (0-indexed)
- env_offset: prod = 0, staging = 1, dev = 2

| CIDR | Account | Tenant | Environment |
|---|---|---|---|
| `10.10.0.0/16` | tenant-a-prod | Tenant-A | prod |
| `10.11.0.0/16` | tenant-a-staging | Tenant-A | staging |
| `10.12.0.0/16` | tenant-a-dev | Tenant-A | dev |
| `10.13.0.0/16` – `10.19.0.0/16` | Reserved | Tenant-A | future expansion |
| `10.20.0.0/16` | tenant-b-prod | Tenant-B | prod |
| `10.21.0.0/16` | tenant-b-staging | Tenant-B | staging |
| `10.22.0.0/16` | tenant-b-dev | Tenant-B | dev |
| `10.23.0.0/16` – `10.29.0.0/16` | Reserved | Tenant-B | future expansion |
| `10.30.0.0/16` | tenant-c-prod | Tenant-C | prod |
| ... | ... | ... | ... |

This pattern supports up to **24 tenants** with 10 blocks each, within `10.10.0.0/8`.

---

## Subnet Layout (standard pattern per /16)

Every VPC follows this internal layout. Substitute `x` with the account's second octet.

```
10.x.0.0/16   ← VPC CIDR
│
├── Public subnets (internet-facing — ALB, NAT Gateway, bastion)
│   ├── 10.x.0.0/24    eu-west-2a
│   └── 10.x.1.0/24    eu-west-2b
│
├── Private subnets (application tier — EKS nodes, EC2, ECS tasks)
│   ├── 10.x.10.0/24   eu-west-2a
│   └── 10.x.11.0/24   eu-west-2b
│
└── DB subnets (data tier — RDS, ElastiCache — no internet, no NAT)
    ├── 10.x.20.0/24   eu-west-2a
    └── 10.x.21.0/24   eu-west-2b
```

Each `/24` provides 251 usable IPs. Add a third AZ (`eu-west-2c`) using `.2`, `.12`, `.22` when needed.

---

## Transit Gateway Routing Strategy

Non-overlapping CIDRs prevent conflicts but do **not** prevent tenant-to-tenant traffic.
TGW route table segregation handles isolation:

```
TGW route tables:

  "shared" route table  ← shared-services VPC attachment
  ┌─────────────────────────────────────┐
  │ 10.0.0.0/16  → management          │
  │ 10.2.0.0/16  → sandbox             │
  │ 10.10.0.0/16 → tenant-a-prod       │
  │ 10.20.0.0/16 → tenant-b-prod       │
  │ ...                                 │
  └─────────────────────────────────────┘
  shared-services can reach ALL accounts (for DNS, ECR, Secrets pulls)

  "tenant-isolated" route table  ← all tenant VPC attachments
  ┌─────────────────────────────────────┐
  │ 10.1.0.0/16  → shared-services     │  ← only shared-services
  └─────────────────────────────────────┘
  Tenants can only reach shared-services.
  Tenant-A CANNOT reach Tenant-B — even though CIDRs don't overlap.
```

Each new tenant VPC attachment is associated with the `tenant-isolated` route table automatically.

---

## Adding a New Account — Checklist

Before writing any Terraform:

1. Pick the next available `/16` from the tenant range (check this table first)
2. Mark it as allocated here (account name + environment)
3. Confirm it does not conflict with any existing entry
4. Add the VPC CIDR to `variables.tf` in the relevant infra repo — no hardcoding

```bash
# Quick conflict check — list all VPC CIDRs across accounts
aws ec2 describe-vpcs --query 'Vpcs[].CidrBlock' --output text --profile management-admin
aws ec2 describe-vpcs --query 'Vpcs[].CidrBlock' --output text --profile shared-services-admin
aws ec2 describe-vpcs --query 'Vpcs[].CidrBlock' --output text --profile sandbox-admin
```

Replace the profile names above with the local SSO profile names in your AWS CLI config.

---

## IPAM Migration Path

| Stage | Accounts | Approach |
|---|---|---|
| Now (POC) | < 5 | Manual — this file is the source of truth |
| Growth | 5–15 | Manual still works — enforce via `validation` block in Terraform variables |
| Scale | 15+ | Migrate to AWS VPC IPAM (~$2/month per /16 monitored) — automates allocation for new accounts |

AWS VPC IPAM integrates with AWS Organizations — new accounts get a CIDR automatically from a pool,
preventing human error in allocation. Set it up before it becomes painful, not after a conflict happens.

---

## Rules

- **Never reuse a CIDR** — even for accounts in different OUs that don't currently connect
- **Never use `10.0.0.0/8` as a VPC CIDR** — it is the master pool, not a VPC range
- **`10.0.0.0/8` supernet routes are test-only** — production route tables use specific `/16` destinations
- **Update this file first** — before opening a PR to add a new account or VPC
