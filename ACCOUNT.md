# Account Management

This document covers the AWS account strategy for this organisation -
what each account does, how accounts are created, and what's planned.

Accounts are managed via `2-organisation/accounts.tf`.
See `2-organisation/README.md` for the three account creation patterns.

---

## Current Account Inventory

| Account | OU | Purpose | Status |
|---------|-----|---------|--------|
| Management (root) | Root | Owns the org. Runs Organizations, Identity Center, Terraform state. No workloads. | Active |
| shared-services | Shared OU | Shared platform tooling - ECR, Route 53, Transit Gateway hub | Active (imported) |
| sandbox | Workloads/Tenant-A | EKS, ALB, NLB, networking POC workloads | Active (created via GitHub Actions) |

---

## Account Purposes in Detail

### Management Account

The "landlord" account. Owns the entire organisation.

```
Runs:
  - AWS Organizations (OU structure, SCPs)
  - IAM Identity Center (SSO for all accounts)
  - Terraform remote state (S3 + DynamoDB)
  - GitHub Actions OIDC role
  - AWS Config org-level rules (when recorder enabled)

Rule: NEVER deploy application workloads here.
      This account has no SCP guardrails on itself.
```

---

### shared-services (Shared OU)

Central shared platform services consumed by all tenant workloads.

```
Planned workloads:
  - Amazon ECR         - container image registry (all tenants pull from here)
  - Amazon Route 53    - DNS for all tenant domains
  - Transit Gateway    - central network hub (all tenant VPCs attach here)
  - Shared tooling     - internal platform tools

Why shared?
  Tenants share one ECR instead of having per-tenant registries.
  One Route 53 hosted zone manages all subdomains.
  One TGW hub enables inter-account networking without VPC peering.
```

---

### sandbox (Workloads/Tenant-A)

Development and POC workload account.

```
Planned workloads:
  - Amazon EKS         - Kubernetes cluster for application workloads
  - Application LB     - HTTP/HTTPS load balancing for services
  - Network LB         - TCP/UDP load balancing, high performance
  - VPC + subnets      - isolated network (attaches to TGW in shared-services)
  - Security Groups    - instance-level firewall
  - NACLs              - subnet-level firewall
  - GuardDuty          - threat detection
  - Security Hub       - compliance monitoring

Cost estimate when running:
  EKS control plane:    ~$72/month
  NAT Gateway:          ~$32-45/month
  ALB:                  ~$16-20/month
  Transit Gateway:      ~$36/month per attachment
  Total:                ~$160-180/month when all running

Remember to destroy EKS and NAT Gateway when not actively testing.
```

---

## Future Planned Accounts

### When Control Tower is Enrolled

Control Tower automatically creates these two mandatory accounts.
Do NOT create them manually - CT owns them.

**log-archive (Security OU)**
```
Purpose: Immutable audit trail for the entire organisation.

All accounts ship here:
  - CloudTrail logs (every API call in every account)
  - AWS Config history snapshots
  - S3 access logs

Why separate account?
  If a workload account is compromised, attackers cannot tamper with logs.
  The logs are in a different account they do not control.
  Required for SOC 2, ISO 27001, and most compliance frameworks.
```

**audit (Security OU)**
```
Purpose: Central security monitoring hub.

Aggregates findings from all accounts:
  - GuardDuty threats (compromised credentials, malware, unusual activity)
  - Security Hub compliance violations
  - AWS Config rule violations
  - Inspector vulnerability findings

Has read-only access to all member accounts.
You log into one account to see the security posture of the whole org.
```

---

### When Adding a Real Tenant (Tenant-B example)

```
Workloads OU
└── Tenant-B OU          ← new OU added to organizations.tf
    ├── tenant-b-dev     ← new account in accounts.tf
    ├── tenant-b-staging ← new account in accounts.tf
    └── tenant-b-prod    ← new account in accounts.tf
                           prod account gets DenyRDS SCPs attached
```

---

### When Scaling to Production (Option B - Networking Account)

```
Shared OU
├── shared-services      ← ECR, Route 53, SES
└── networking           ← dedicated connectivity account
                           Transit Gateway (moved from shared-services)
                           Shared VPCs
                           Network monitoring (VPC Flow Logs aggregation)
                           Direct Connect / VPN termination
```

Separate networking account is recommended when:
- Multiple tenants with strict network isolation requirements
- Direct Connect or VPN for on-premises connectivity
- Centralised network monitoring and flow log analysis

---

## Account Creation Workflow

### New account via GitHub Actions (recommended)

All new accounts go through a PR review - creating an AWS account has a
90-day closure commitment, so human approval is required.

```
0. Allocate a CIDR in CIDR.md FIRST
   - Pick the next available /16 from the tenant range
   - Mark it as allocated (account name + environment)
   - Confirm no conflict with existing entries
   - This must be done before writing any Terraform

1. Add resource block to 2-organisation/accounts.tf
   (one block per account - see template below)

2. Open a PR on a branch
   - GitHub Actions runs terraform plan
   - Plan shows: account name, OU, tags

3. Team reviews the plan
   - Correct OU?
   - Correct email? (must be globally unique)
   - Correct tags for billing?
   - CIDR.md updated with the new allocation?

4. Merge to main
   - org-production environment gate triggers
   - Reviewer approves in GitHub

5. terraform apply creates the account (~2 minutes)

6. Post-creation baseline (manual in this POC; AFT remains code-only unless applied later):
   - Switch role into new account
   - Enable GuardDuty
   - Enable Security Hub
   - Enable Config recorder
   OR use AWS Systems Manager Quick Setup to cover all accounts at once
```

### Account resource template

```hcl
resource "aws_organizations_account" "your_account_name" {
  name      = "account-name"           # appears in AWS console
  email     = var.your_account_email   # must be globally unique
  parent_id = aws_organizations_organizational_unit.target_ou.id

  close_on_deletion = false  # removing from code does NOT close the account

  lifecycle {
    prevent_destroy = true   # terraform refuses to destroy without explicit override
  }

  tags = {
    tenant      = "tenant-name"
    environment = "dev"
    managed_by  = "terraform"
  }
}
```

### Importing an existing account

For accounts created manually or before Terraform management:

```bash
# Step 1 - add the resource block to accounts.tf first
# Step 2 - import the account into state (run locally, one-time)
terraform import aws_organizations_account.your_account_name ACCOUNT_ID

# Step 3 - verify no unintended changes
terraform plan  # should show: no changes

# Step 4 - commit the accounts.tf change via normal PR workflow
```

---

## Email Convention

AWS requires a globally unique email per account. Use aliases:

```
Pattern: aws+ACCOUNT-NAME@yourdomain.com

Examples:
  aws+shared-services@yourdomain.com
  aws+sandbox@yourdomain.com
  aws+tenant-a-dev@yourdomain.com
  aws+log-archive@yourdomain.com
```

All aliases route to one inbox. Replace `yourdomain.com` with your actual domain.

---

## Account Baseline Checklist

After every new account is created, complete this baseline.
In this POC, AFT is written as code-only documentation, so this remains manual
unless AFT is deliberately applied later:

- [ ] GuardDuty enabled
- [ ] Security Hub enabled (AWS Foundational + CIS standards)
- [ ] Config recorder started
- [ ] MFA enabled on root user of new account
- [ ] Root access keys confirmed absent
- [ ] SSO permission set assigned (at minimum ReadOnlyAccess)
- [ ] Account tagged correctly in Organizations
