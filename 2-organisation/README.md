# Layer 2 - Organisation

This layer manages the AWS organisation structure - OUs, SCPs, SSO, GitHub OIDC, and Config rules. It runs via GitHub Actions after the first manual apply (which creates the OIDC role that GitHub Actions needs).

## Prerequisites

Before applying this layer:

**1. IAM Identity Center must be enabled**
Identity Center is enabled once per organisation - not per account, not per region.
```
AWS Console → IAM Identity Center → Enable
Choose: Enable with AWS Organizations (organisation instance)
Primary region: eu-west-2
```

**2. Layer 1 (bootstrap) must be applied**
The S3 bucket and DynamoDB table from bootstrap must exist before this layer can store its state.

**3. First apply must be local**
The GitHub Actions OIDC role is created by this layer - which means GitHub Actions cannot authenticate until after the first apply. Run the first apply locally using the `org-bootstrap` profile. All future changes go through GitHub Actions.

## Files in This Layer

| File | What it creates |
|------|----------------|
| `backend.tf` | S3 remote state config |
| `main.tf` | Provider config |
| `variables.tf` | Input variables |
| `outputs.tf` | OU IDs, role ARN, SSO instance ARN |
| `organizations.tf` | OUs - Security, Shared, Workloads, Tenant-A |
| `scp_global.tf` | 4 SCPs attached to Root |
| `scp_workloads.tf` | 2 SCPs attached to Workloads OU |
| `scp_prod.tf` | 2 SCPs created (attachments pending prod accounts) |
| `config_rules.tf` | 6 org Config rules (commented out - see Config section) |
| `identity_center.tf` | 3 SSO permission sets |
| `github_oidc.tf` | GitHub Actions OIDC provider + IAM role |

## Running This Layer

```bash
export AWS_PROFILE=org-bootstrap   # first apply only
cd 2-organisation/

cp terraform.tfvars.example terraform.tfvars
# Fill in: management_account_id, github_org

terraform init
terraform plan    # review carefully before applying
terraform apply
```

---

## Region Strategy

| Component | Region | Reason |
|-----------|--------|--------|
| Control Tower home | `eu-west-2` | Management plane |
| AFT pipeline | `eu-west-2` | Runs in management account |
| Terraform state | `eu-west-2` | Management account |
| Workloads | Defined per tenant | Set in each account request |

---

## Control Tower

Control Tower is AWS's managed Landing Zone. It automates the creation of mandatory security accounts and baseline guardrails.

```
✅ Security OU + Log Archive + Audit accounts
✅ Org-level CloudTrail (all accounts)
✅ AWS Config (all accounts)
✅ IAM Identity Center (SSO)
✅ Pre-built guardrails (SCPs)
```

**Home region:** `eu-west-2`

> **POC note:** Control Tower is not enrolled to avoid mandatory account costs (~$15–30/month). It will be enrolled when moving to production.

---

## SCP Reference

AWS hard limit: **5 SCPs per target** (Root, OU, or account). The default `FullAWSAccess` SCP counts as 1, leaving 4 slots for custom SCPs.

### Global SCPs - attached to Root (all accounts)

**DenyUnsupportedRegions**
Blocks any AWS action outside approved regions. Uses `NotAction` to exclude global services (IAM, STS, Route 53, CloudFront) that have no regional endpoint.
```
Allowed regions: eu-west-2, ap-southeast-2
```

**DenyIAMUserCreation**
Blocks `iam:CreateUser` and `iam:CreateAccessKey`. SSO is the only permitted access method.

**DenySecurityMonitoringDisable** *(consolidated - CloudTrail + GuardDuty + Config)*
Consolidated into one policy to stay within the 5-SCP limit:
- CloudTrail: `DeleteTrail`, `StopLogging`, `UpdateTrail`, `PutEventSelectors`
- GuardDuty: `DeleteDetector`, `DisassociateFromMasterAccount`, `StopMonitoringMembers`, `UpdateDetector`
- Config: `StopConfigurationRecorder`, `DeleteConfigurationRecorder`, `DeleteDeliveryChannel`

**DenyPublicS3**
Blocks setting public ACLs on S3 buckets and objects.

### Workloads OU SCPs - attached to Workloads OU

**DenyCrossTenantVpcPeering**
Blocks `ec2:AcceptVpcPeeringConnection`. Tenants cannot peer VPCs with each other.

**RequireMandatoryTags**
Blocks creating key resources without required tags: `tenant`, `environment`, `project`.

### Prod SCPs - policies created, attachments pending

> **Status:** Not yet attached. Add attachments in `scp_prod.tf` when prod accounts exist.
>
> **Attachment options:**
> - Option A: Attach directly to the prod account ID
> - Option B: Create a `Prod` sub-OU under each Tenant OU (recommended for production)

**DenyRDSBackupDeletion** - Blocks deleting RDS snapshots and disabling automated backups.

**DenyRDSPublicAccess** - Blocks making RDS instances publicly accessible.

---

## AWS Config Rules

> **Current status: Config rules are commented out in `config_rules.tf`.**
> Config recorder must be enabled in each account before rules can evaluate.

Config rules are **per region** - each rule evaluates resources only in the region it was deployed (`eu-west-2`). To cover `ap-southeast-2`, create the same rules using a provider alias for that region.

Config recorder is **per account AND per region** - no org-wide recorder exists:
- Each account needs its own recorder per region
- Example: 10 accounts × 2 regions = 20 recorders

### Enabling Config Recorder Org-Wide

**Option A - AWS Systems Manager Quick Setup** *(fastest)*
```
AWS Console → Systems Manager → Quick Setup
→ Config Recording → All accounts → All regions → Deploy
```

**Option B - CloudFormation StackSets** *(code-driven)*
Deploy a CloudFormation stack to all accounts and regions simultaneously.

**Option C - AFT global customisations** *(automatic for future accounts)*
`3-aft/account-customizations/global/baseline-iam.tf` enables the recorder in every AFT-vended account.

### Enabling Config Recorder Manually (Single Account)

```
1. Switch into the account via OrganizationAccountAccessRole

2. AWS Console → AWS Config → Get started
   → Record all resources
   → Create AWS Config service-linked role (auto)
   → Create new S3 bucket for delivery
   → Confirm

3. Verify: AWS Config → Settings → Recording is ON

4. Repeat for each region (eu-west-2, ap-southeast-2)
```

### Applying Config Rules After Recorder is Enabled

Uncomment resource blocks in `config_rules.tf`, then:
```bash
terraform apply \
  -target=aws_config_organization_managed_rule.rds_public_access \
  -target=aws_config_organization_managed_rule.s3_public_read \
  -target=aws_config_organization_managed_rule.s3_public_write \
  -target=aws_config_organization_managed_rule.root_mfa_enabled \
  -target=aws_config_organization_managed_rule.root_access_key_check \
  -target=aws_config_organization_managed_rule.encrypted_volumes
```

| Rule | Checks |
|------|--------|
| `rds-instance-public-access-check` | RDS not publicly accessible |
| `s3-bucket-public-read-prohibited` | No public S3 read |
| `s3-bucket-public-write-prohibited` | No public S3 write |
| `root-account-mfa-enabled` | Root MFA enabled |
| `iam-root-access-key-check` | Root has no access keys |
| `encrypted-volumes` | EBS volumes encrypted |

**SCP vs Config rule:**

| | SCP | Config Rule |
|--|-----|-------------|
| What it does | Prevents the action | Detects non-compliance |
| When | Real-time at API call | After resource exists |
| Response | Action fails immediately | Flags as NON_COMPLIANT |

---

## IAM Identity Center (SSO)

All human access goes through SSO. No IAM users anywhere.

### Accessing the Console via SSO

**Step 1 - Login via CLI:**
```bash
aws sso login --profile YOUR_PROFILE
```

**Step 2 - Open the SSO portal in your browser:**
```
https://d-xxxxxxxxxx.awsapps.com/start/
```
Replace with your actual SSO start URL (found in Identity Center → Settings).
Select the account → click "Management console".

**Step 3 - Verify which account you are in:**
```bash
aws sts get-caller-identity --profile YOUR_PROFILE
```

**Profile quick reference:**

| Profile | Account | Used for |
|---------|---------|---------|
| `org-bootstrap` | Management | Local Terraform runs, break-glass only |
| `my-admin` | Management | Day-to-day admin via SSO |
| `my-sandbox` | Sandbox | EKS, networking, application POC |

> **Note:** Profile names are personal - use your own naming convention.
> The `sso_session` block is shared across profiles pointing to the same Identity Center instance.
> One `aws sso login` refreshes all profiles sharing the same session.

### Permission Sets

| Permission Set | Policy | Session | Used For |
|---------------|--------|---------|---------|
| `AdministratorAccess` | AWS managed | 4 hours | Org admins |
| `ReadOnlyAccess` | AWS managed | 8 hours | Auditors |
| `DeployAccess` | Inline (ECR, ECS, S3, Secrets) | 1 hour | App CI/CD pipelines |

> **DeployAccess is for application deployment, not Terraform.** See the table below for the right tool per scenario.

| Scenario | What to use |
|----------|-------------|
| Terraform for org infrastructure (this repo) | GitHub OIDC role - `github_oidc.tf` |
| Terraform for tenant infrastructure | New OIDC role per repo - add to `github_oidc.tf` |
| Engineer running Terraform manually | `AdministratorAccess` permission set via SSO |
| CI/CD deploying applications to a tenant account | `DeployAccess` permission set |

### How Permission Sets Work - The Role Behind the Scenes

A permission set is a blueprint. When assigned to a user + account, Identity Center automatically creates a real IAM role in that account:

```
Permission Set (blueprint - management account)
        ↓ assigned to user + account
AWSReservedSSO_AdministratorAccess_<random> created in member account
        ↓
User logs in via SSO portal → SAML assertion → STS assumes that role
        ↓
Temporary credentials issued for the session duration
        ↓
Credentials expire at end of session
```

This role is created **once** when the assignment is made and reused on every login.

### Assigning Users to Accounts

User assignments are **not managed in this Terraform repo** - usernames are personal data not appropriate for a public repo.

**Option A - Manual in console**
```
Identity Center → AWS accounts → [select account]
→ Assign users or groups → [select john.doe]
→ [select permission set] → Submit
```
Wait ~1 minute. Then add the profile to `~/.aws/config`:
```ini
[profile my-admin]
sso_session = my-org
sso_account_id = 123456789012
sso_role_name = AdministratorAccess
region = eu-west-2

[sso-session my-org]
sso_start_url = https://d-xxxxxxxxxx.awsapps.com/start/
sso_region = eu-west-2
sso_registration_scopes = sso:account:access
```
Find your SSO start URL: `Identity Center → Settings → AWS access portal URL`

Test:
```bash
aws sso login --profile my-admin
aws sts get-caller-identity --profile my-admin
```

**Option B - Terraform with gitignored variables**
See commented assignment block in `identity_center.tf`. Store user IDs in `terraform.tfvars` (gitignored).

**Option C - SCIM sync from external IdP (recommended for production)**
```
Identity Center → Settings → Identity source
→ External identity provider → Follow SCIM guide for Okta / Azure AD / Google Workspace
```
Users sync automatically. Terraform only manages permission sets - never individual users.

---

## GitHub Actions - OIDC Authentication

### How the Provider and Role Are Linked

```
GitHub Actions job starts
        ↓
GitHub issues a short-lived JWT token:
  aud: sts.amazonaws.com
  sub: repo:YOUR_ORG/aws-org-infra:ref:refs/heads/main
        ↓
AWS checks the role trust policy:
  1. Token signed by token.actions.githubusercontent.com?  ✅
  2. aud = sts.amazonaws.com?                              ✅
  3. sub matches repo:YOUR_ORG/aws-org-infra:*?            ✅
        ↓
Temporary credentials issued (1 hour max)
        ↓
Credentials expire when the job ends
```

All GitHub Actions roles for all repos are defined in `github_oidc.tf` - one central place for all trust relationships.

### OIDC Thumbprint

The thumbprint is the SHA-1 of GitHub's TLS root certificate. Fetch the current value via:
```
IAM → Identity providers → token.actions.githubusercontent.com
→ Manage thumbprints → Get thumbprint
```
Update `github_oidc.tf` if GitHub rotates their TLS certificate.

---

## Naming Conventions

### AWS Resources
```
Pattern: {layer}-{component}

Examples:
  org-terraform-state          ← S3 state bucket
  org-terraform-locks          ← DynamoDB table
  org-github-actions-role      ← OIDC IAM role
```

### OUs
```
Security
Shared
Workloads
Workloads/Tenant-A
```

### Accounts
```
Platform:  log-archive, audit, shared-services
Tenant:    tenant-a-dev, tenant-a-staging, tenant-a-prod
```

---

## Account Creation

AWS accounts are managed via `accounts.tf` in this layer. No AFT required.
One Terraform resource block = one AWS account. Git-driven, fully auditable.

### Pattern 1 - Terraform `aws_organizations_account` (recommended)

This is what we use. Every account is a resource block in `accounts.tf`.

**Creating a new account:**
```hcl
resource "aws_organizations_account" "tenant_a_dev" {
  name      = "tenant-a-dev"
  email     = var.tenant_a_dev_email
  parent_id = aws_organizations_organizational_unit.tenant_a.id

  # close_on_deletion = false (default):
  # Removing this block from code does NOT close the real AWS account.
  # Terraform just stops tracking it. The account continues to exist.
  close_on_deletion = false

  # prevent_destroy = true:
  # Terraform refuses to destroy this resource unless you explicitly
  # remove this flag first. Protects against accidental account removal.
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    tenant      = "tenant-a"
    environment = "dev"
    managed_by  = "terraform"
  }
}
```

**Approval flow:**
```
Engineer creates tenant-a-dev.tf on a branch
        ↓
PR opened - GitHub Actions runs terraform plan
        ↓
Plan shows: 1 account to create, in correct OU with correct tags
        ↓
Team reviews the plan in the PR
        ↓
PR merged - org-production environment gate triggers
        ↓
Reviewer approves in GitHub
        ↓
terraform apply creates the account (~2 minutes)
```

**Importing an existing account into Terraform management:**

If an account already exists (created manually or via console), import it rather than recreating:
```bash
# General pattern - replace with your actual account ID
terraform import aws_organizations_account.your_account_name YOUR_ACCOUNT_ID

# Example
terraform import aws_organizations_account.sandbox 123456789012
```

Then add the matching resource block to `accounts.tf` with `prevent_destroy = true`.

> **Note on email addresses:** AWS requires a globally unique email per account.
> Use email aliases: `aws+tenant-a-dev@yourdomain.com`
> All aliases can route to the same inbox.

**What this does NOT do automatically (unlike AFT):**
- Enable GuardDuty in the new account
- Enable Security Hub
- Start the Config recorder

After account creation, either enable these manually (switch role → console)
or use AWS Systems Manager Quick Setup to baseline all accounts at once.

---

### Pattern 2 - AWS Service Catalog Account Vending Machine (AVM)

A lighter AWS-native alternative to AFT. Uses AWS Service Catalog to offer an
"account request" product that engineers can order via a self-service portal.

**How it works:**
```
Admin creates a Service Catalog Portfolio + Product (account template)
        ↓
Engineer goes to Service Catalog → launches the product
        ↓
Fills in: account name, email, OU, tags
        ↓
CloudFormation creates the account via Organizations API
        ↓
Optional: CloudFormation StackSet runs baseline config in the new account
```

**Pros vs AFT:**
- No NAT Gateway - no ongoing cost
- No CodePipeline to maintain
- Native AWS UI - no GitHub dependency
- Simpler to set up

**Cons vs AFT:**
- Not git-driven (console-based, not PR-based)
- Less automation - customisations need StackSets separately
- Harder to version control account requests

**When to use:** When you want a self-service portal without the full AFT pipeline cost,
and your team is comfortable with the AWS console.

---

### Pattern 3 - AWS CLI + Terraform Import (hybrid)

The simplest approach. Create accounts manually via CLI, then bring them under
Terraform management via import.

**Step 1 - Create the account via CLI:**
```bash
aws organizations create-account \
  --account-name "tenant-a-dev" \
  --email "aws+tenant-a-dev@yourdomain.com" \
  --iam-user-access-to-billing ALLOW \
  --profile org-bootstrap

# Check creation status (takes 1-2 minutes)
aws organizations describe-create-account-status \
  --create-account-request-id <request-id-from-above> \
  --profile org-bootstrap
```

**Step 2 - Add the resource block to accounts.tf:**
```hcl
resource "aws_organizations_account" "tenant_a_dev" {
  name      = "tenant-a-dev"
  email     = var.tenant_a_dev_email
  parent_id = aws_organizations_organizational_unit.tenant_a.id

  close_on_deletion = false
  lifecycle { prevent_destroy = true }
}
```

**Step 3 - Import into Terraform state:**
```bash
terraform import aws_organizations_account.tenant_a_dev ACCOUNT_ID_FROM_STEP_1
```

**Step 4 - Verify:**
```bash
terraform plan  # should show: no changes
```

**When to use:** One-off account creation where you need it immediately without
waiting for a PR review cycle. Import brings it under proper management afterwards.
