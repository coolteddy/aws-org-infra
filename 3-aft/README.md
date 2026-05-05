# Layer 3 - AFT (Account Factory for Terraform)

> **STATUS: CODE ONLY - DO NOT APPLY IN POC**
>
> AFT code is written with educational comments but never applied in this POC.
> Cost when live: ~$40–55/month (NAT Gateway runs 24/7).
> Each vended account has a 90-day closure wait before it can be deleted.
> Apply this layer only when moving to production.

## What AFT Does

AFT replaces manual account creation with a Git commit:

```
Commit a new file to account-requests/
        ↓
CodePipeline detects the change
        ↓
Control Tower creates the AWS account
        ↓
AFT runs global customisations (GuardDuty, Security Hub, Config recorder)
        ↓
Account is ready - SSO access configured (~20 minutes)
```

## Prerequisites

Before applying AFT:
1. **Control Tower must be enrolled** - AFT requires Control Tower as its foundation
2. **Layer 2 must be applied** - AFT uses the S3 remote state backend
3. **Log Archive and Audit account IDs** - created by Control Tower, needed as inputs

## What AFT Deploys (When Applied)

| Component | Cost |
|-----------|------|
| VPC + NAT Gateway | ~$32–45/month (always running) |
| CodePipeline | ~$1/month |
| CodeBuild | ~$1–3/month (build minutes) |
| Step Functions | ~$0–1/month |
| Lambda, SQS, SNS | ~$0–1/month |
| S3, DynamoDB | ~$1–2/month |

## Files in This Layer

```
3-aft/
├── backend.tf                     Remote state (same bucket, key = aft/terraform.tfstate)
├── main.tf                        AFT module call (fully commented)
├── variables.tf                   Account IDs, emails, GitHub org
├── outputs.tf                     Pipeline ARNs (commented)
├── terraform.tfvars.example       Safe placeholder values
├── account-requests/
│   ├── README.md                  How to add a new account
│   ├── log-archive.tf             Mandatory CT account
│   ├── audit.tf                   Mandatory CT account
│   └── shared-services.tf        Shared ECR, Route 53, SES
└── account-customizations/
    └── global/
        ├── README.md              What customisations do and why
        ├── guardduty.tf           Enables GuardDuty in every account
        ├── security-hub.tf        Enables Security Hub + compliance standards
        └── baseline-iam.tf       IAM password policy + Config recorder
```

## Adding a New Tenant Account

1. Create a new file in `account-requests/` (copy an existing one as template)
2. Update `AccountName`, `AccountEmail`, `ManagedOrganizationalUnit`, tags
3. Commit to a branch → GitHub Actions runs `terraform plan`
4. Review the plan in the PR
5. Merge to main → AFT provisions the account (~20 minutes)
6. Login via SSO: `aws sso login --profile tenant-a-dev`

See `account-requests/README.md` for the full pattern.

## Account Customisations

Every vended account automatically gets:

| Customisation | Why |
|--------------|-----|
| GuardDuty enabled | Threat detection from day one |
| Security Hub enabled | Compliance visibility from day one |
| Config recorder started | Enables org Config rules to evaluate this account |
| IAM password policy | Baseline security for any IAM users |

See `account-customizations/global/README.md` for details.
