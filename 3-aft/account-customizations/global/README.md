# Account Customisations — Global

These files run automatically in **every account** vended by AFT, immediately after the account is created.

Think of this as a baseline setup script — every account gets the same security foundation regardless of which tenant it belongs to.

## What Runs in Every Account

| File | What it does | Why |
|------|-------------|-----|
| `guardduty.tf` | Enables GuardDuty threat detection | Detects compromised credentials, malware, unusual activity |
| `security-hub.tf` | Enables Security Hub + compliance standards | Central dashboard for security findings and compliance scoring |
| `baseline-iam.tf` | Sets IAM password policy + enables Config recorder | Enforces password security; enables Config rules to evaluate |

## Why This Matters

Without these customisations, every new account is a blank slate:
- No threat detection (GuardDuty off by default)
- No compliance visibility (Security Hub off by default)
- No Config recorder (org Config rules cannot evaluate — see `2-organisation/config_rules.tf`)

This is exactly the problem we hit in the POC when applying Config rules: `NoAvailableConfigurationRecorder`. If AFT was deployed, `baseline-iam.tf` would solve it automatically in every account.

## Adding Account-Specific Customisations

For customisations that only apply to specific account types (e.g. prod-only hardening), create a new folder alongside `global/`:

```
account-customizations/
├── global/          ← runs in every account
└── prod/            ← runs only in accounts that specify account_customizations_name = "prod"
```

In the account request file, set:
```hcl
account_customizations_name = "prod"
```
