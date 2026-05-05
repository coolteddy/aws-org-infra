# Account Requests

One file = one AWS account.

Committing a new `.tf` file here triggers the AFT pipeline which provisions the account automatically via Control Tower (~20 minutes).

## Adding a New Tenant Account

1. Copy an existing file (e.g. `shared-services.tf`) as a template
2. Update:
   - `AccountName` — unique name for the account
   - `AccountEmail` — unique email (AWS requires one email per account)
   - `ManagedOrganizationalUnit` — which OU it belongs to (e.g. `Workloads/Tenant-A`)
   - `account_tags` — update `tenant` and `purpose`
3. Commit to a branch → GitHub Actions runs `terraform plan`
4. Review the plan in the PR
5. Merge to main → AFT provisions the account

## Account Naming Convention

```
Platform accounts:  log-archive, audit, shared-services
Tenant accounts:    tenant-a-dev, tenant-a-staging, tenant-a-prod
```

## Important Notes

- Each account email must be globally unique — AWS does not allow reuse
- Use email aliases: `aws+tenant-a-dev@yourdomain.com`
- Accounts created via AFT have a **90-day closure wait** before they can be deleted
- The `account_customizations_name = "global"` line ensures GuardDuty,
  Security Hub, and baseline IAM run automatically in every new account
