# FinOps Plan — AWS Cost Management

**FinOps = treating cloud cost like code.**
Engineers see cost impact before merging. Spend is visible per tenant, per account, per service.
Anomalies are caught automatically. Dev environments shut down when nobody is using them.

> **Status: post-testing** — implement after TGW test + security baseline are validated.

---

## What FinOps Is NOT

- Not just "set a budget alert and check the bill monthly"
- Not the finance team's problem
- Not something you bolt on later without pain

FinOps is an engineering discipline. The earlier you build it in, the cheaper it is to run.

---

## Maturity Levels

### Crawl — Visibility (implement now, during testing)

You cannot optimise what you cannot see.

| Tool | What it does | Cost | Effort |
|---|---|---|---|
| **Cost Anomaly Detection** | ML-based spike detection per account/service. Alerts before the bill arrives. | Free | 10 min |
| **AWS Budgets** | Monthly spend threshold per account. Alert + auto-action when exceeded. | Free (first 2 budgets) | 15 min |
| **Cost Allocation Tags** | Activate existing `tenant`, `environment`, `project` tags in Billing console. Cost Explorer breaks down spend per tag. | Free | 5 min |
| **Cost Explorer** | Visual spend breakdown by account, service, tag, region. Free to view. | Free | 0 min — already available |

**Do these now.** They cost nothing and protect you during testing (especially EKS at $72/month).

---

### Walk — Optimisation (after first real workload is running)

| Tool | What it does | Cost | When |
|---|---|---|---|
| **Infracost** | Shows cost delta of every Terraform PR as a GitHub Actions comment. Engineers see "+$72/month" before merging EKS. | Free for small teams | Add to all repo GitHub Actions |
| **Lambda auto-shutdown** | Stops sandbox EKS + RDS on evenings/weekends. Saves ~70% of sandbox compute. | ~$0 (Lambda free tier) | When EKS first runs |
| **Compute Optimizer** | Analyses 14 days of CloudWatch metrics. Flags oversized instances. "This RDS is using 3% CPU — downsize." | Free | After 2 weeks of real workloads |
| **S3 Intelligent Tiering** | Automatically moves log-archive objects to cheaper tiers after 30/90 days. | $0.0025/1000 objects monitored | When log-archive has real data |

---

### Run — Automation (production / Loadberry org)

| Tool | What it does | Cost | When |
|---|---|---|---|
| **Budget Actions** | Automatically applies a `DenyExpensiveServices` SCP when an account exceeds its budget. No manual intervention. | Free | When tenants are paying customers |
| **Savings Plans** | Commit to $X/hour of compute for 1–3 years. 30–66% discount on EKS nodes, EC2, Fargate. | Commitment only | After 3+ months of stable workloads |
| **Spot Instances / Karpenter** | EKS worker nodes on spot instances. Up to 90% cheaper. Auto-fallback to on-demand. | Savings only | EKS production workloads |
| **Reserved Instances (RDS)** | 1-year commit on RDS instance class. ~40% saving on the $15/month db.t3.micro. | Commitment only | After tenant count stabilises |
| **Chargeback reporting** | Per-tenant cost breakdown using Cost Allocation Tags. Feeds into tenant billing. | Free (Cost Explorer API) | When billing tenants |

---

## Implementation Plan (in order)

### Phase 1 — During testing (do now, zero cost)

**Step 1: Activate Cost Allocation Tags**
```
AWS Console → Billing → Cost Allocation Tags
Activate: tenant, environment, project, managed_by
Wait 24 hours for tags to appear in Cost Explorer
```

**Step 2: Enable Cost Anomaly Detection**
```hcl
# Add to aws-org-infra/2-organisation/ — new file: cost_anomaly.tf
resource "aws_ce_anomaly_monitor" "org" {
  name         = "loadberry-org-monitor"
  monitor_type = "DIMENSIONAL"
  monitor_dimension = "SERVICE"
}

resource "aws_ce_anomaly_subscription" "alert" {
  name      = "loadberry-cost-spike-alert"
  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_PERCENTAGE"
      values        = ["20"]   # alert if spend 20% above expected
      match_options = ["GREATER_THAN_OR_EQUAL"]
    }
  }
  frequency = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.org.arn]
  subscriber {
    address = var.billing_alert_email
    type    = "EMAIL"
  }
}
```

**Step 3: Set per-account Budgets**
```hcl
# Sandbox — alert at $50, hard stop at $150 via SCP action
resource "aws_budgets_budget" "sandbox" {
  name         = "sandbox-monthly"
  budget_type  = "COST"
  limit_amount = "50"
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80        # alert at 80% of $50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.billing_alert_email]
  }
}
```

---

### Phase 2 — Add Infracost to GitHub Actions

Add to each repo's plan workflow (`.github/workflows/*-plan.yml`):

```yaml
- name: Setup Infracost
  uses: infracost/actions/setup@v3
  with:
    api-key: ${{ secrets.INFRACOST_API_KEY }}

- name: Generate Infracost diff
  run: |
    infracost diff --path . \
      --format json \
      --out-file /tmp/infracost.json

- name: Post Infracost comment
  uses: infracost/actions/comment@v3
  with:
    path: /tmp/infracost.json
    behavior: update   # updates existing comment on re-push
```

Free API key at infracost.io. Engineers see cost delta on every PR.

---

### Phase 3 — Lambda auto-shutdown (when EKS is running)

```python
# Runs on cron: weekdays 7pm stop, 8am start. Weekends: off entirely.
# Targets: EKS node groups, RDS instances in sandbox account

import boto3

def handler(event, context):
    action = event['action']  # 'stop' or 'start'

    eks = boto3.client('eks', region_name='eu-west-2')
    rds = boto3.client('rds', region_name='eu-west-2')

    if action == 'stop':
        # Scale EKS node group to 0
        eks.update_nodegroup_config(
            clusterName='sandbox-cluster',
            nodegroupName='default',
            scalingConfig={'minSize': 0, 'maxSize': 3, 'desiredSize': 0}
        )
        # Stop RDS
        rds.stop_db_instance(DBInstanceIdentifier='sandbox-postgres')

    elif action == 'start':
        eks.update_nodegroup_config(
            clusterName='sandbox-cluster',
            nodegroupName='default',
            scalingConfig={'minSize': 1, 'maxSize': 3, 'desiredSize': 1}
        )
        rds.start_db_instance(DBInstanceIdentifier='sandbox-postgres')
```

Schedule via EventBridge cron in `aws-sandbox-infra`.

**Estimated saving: EKS $72 → ~$17/month. RDS $15 → ~$4/month.**

---

### Phase 4 — Budget Actions (production)

When tenants are live, attach a `DenyExpensiveServices` SCP automatically if an account overspends:

```hcl
resource "aws_budgets_budget_action" "deny_expensive" {
  budget_name        = aws_budgets_budget.sandbox.name
  action_type        = "APPLY_SCP_POLICY"
  approval_model     = "AUTOMATIC"
  notification_type  = "ACTUAL"

  action_threshold {
    action_threshold_type  = "ABSOLUTE_VALUE"
    action_threshold_value = 150   # $150 hard stop
  }

  definition {
    scp_action_definition {
      policy_id  = aws_organizations_policy.deny_expensive_services.id
      target_ids = [var.sandbox_account_id]
    }
  }
}
```

---

## Per-Tenant Cost Visibility (chargeback)

With Cost Allocation Tags active and every resource tagged `tenant = tenant-a`:

```bash
# Pull per-tenant monthly spend via CLI
aws ce get-cost-and-usage \
  --time-period Start=2026-05-01,End=2026-06-01 \
  --granularity MONTHLY \
  --filter '{"Tags":{"Key":"tenant","Values":["tenant-a"]}}' \
  --metrics BlendedCost \
  --profile management-admin
```

Use this to: build tenant invoices, identify your most expensive customers, decide pricing.

---

## Monthly Cost Targets (POC)

| Account | Target | Hard limit | Action at limit |
|---|---|---|---|
| Management | ~$0 | $20 | Email alert |
| shared-services | ~$75 (TGW) | $150 | Email alert |
| sandbox | ~$20 (testing) | $50 | Email + SCP action |
| log-archive | ~$1 | $10 | Email alert |
| audit | ~$5 | $20 | Email alert |
| **Total org** | **~$100** | **$200** | Email co-founders |

---

## Files to Create (when implementing)

| File | Repo |
|---|---|
| `cost_anomaly.tf` | aws-org-infra/2-organisation/ |
| `budgets.tf` | aws-org-infra/2-organisation/ |
| `lambda_scheduler.tf` + `scheduler.py` | aws-sandbox-infra/ |
| Infracost step in `*-plan.yml` | All repos |
