# Monitoring Plan — Operational Observability

**Operational monitoring = is my application healthy right now?**
This is separate from security monitoring (GuardDuty, Security Hub, CloudTrail) which is covered in `SECURITY-INFRA-TEST-PLAN.md`.

> **Status: post-testing** — implement after TGW test passes. See `MASTER-TEST-PLAN.md` for sequencing.

---

## Security Monitoring vs Operational Monitoring

| | Security Monitoring | Operational Monitoring |
|---|---|---|
| **Question** | Was anything attacked or misconfigured? | Is my app healthy right now? |
| **Tools** | GuardDuty, Security Hub, CloudTrail, Config | CloudWatch, Container Insights, Grafana |
| **Audience** | Security team, auditors | Engineers, on-call |
| **Repo** | aws-security-infra | aws-sandbox-infra + aws-shared-services-infra |
| **File** | SECURITY-INFRA-TEST-PLAN.md | This file |

---

## Architecture

```
sandbox account                         shared-services account
───────────────                         ───────────────────────
VPC Flow Logs ──────────────────────→ S3 bucket (logs)
ALB access logs ────────────────────→ S3 bucket (logs)
RDS error/slow logs ────────────────→ CloudWatch Logs
EKS pod logs (Fluent Bit) ──────────→ CloudWatch Logs
                                                │
CloudWatch Alarms ──────────────────→ SNS topic (central hub)
GuardDuty finding ──────────────────→ EventBridge → SNS topic
                                                │
                                        Lambda function
                                        (SNS → Discord format)
                                                │
                                        Discord webhook
                                        #loadberry-aws-alerts
                                                │
                                        Grafana workspace
                                        (CloudWatch data source)
                                        cross-account dashboards
```

---

## Discord Alerting via Lambda

AWS Chatbot does not support Discord. Route via Lambda instead:

```
CloudWatch Alarm → SNS → Lambda → Discord webhook
GuardDuty finding → EventBridge → SNS → Lambda → Discord webhook
```

### Step 1 — Create Discord webhook

```
Discord server → #loadberry-aws-alerts channel
→ Edit Channel → Integrations → Webhooks → New Webhook
→ Copy Webhook URL
→ Store in AWS Secrets Manager (not hardcoded in Lambda)
```

### Step 2 — Lambda function (in aws-shared-services-infra)

```python
import json
import os
import urllib.request

# Colour codes: red = ALARM, green = OK, orange = INSUFFICIENT_DATA
COLOURS = {"ALARM": 16711680, "OK": 65280, "INSUFFICIENT_DATA": 16744272}

def handler(event, context):
    sns_record  = event['Records'][0]['Sns']
    subject     = sns_record.get('Subject', 'AWS Alert')

    # GuardDuty findings come as raw JSON, CloudWatch alarms come parsed
    try:
        body = json.loads(sns_record['Message'])
    except Exception:
        body = {"NewStateValue": "ALARM", "AlarmName": subject, "NewStateReason": sns_record['Message']}

    state       = body.get('NewStateValue', 'ALARM')
    alarm_name  = body.get('AlarmName', subject)
    reason      = body.get('NewStateReason', 'See AWS console for details')
    account_id  = body.get('AWSAccountId', 'unknown')
    region      = body.get('Region', 'eu-west-2')

    emoji = "🚨" if state == "ALARM" else "✅"

    discord_payload = {
        "embeds": [{
            "title": f"{emoji} {alarm_name}",
            "description": reason,
            "color": COLOURS.get(state, 16711680),
            "fields": [
                {"name": "State",   "value": state,      "inline": True},
                {"name": "Account", "value": account_id, "inline": True},
                {"name": "Region",  "value": region,     "inline": True}
            ],
            "footer": {"text": "Loadberry AWS Monitoring"}
        }]
    }

    # Webhook URL stored in Secrets Manager — fetched at runtime
    webhook_url = os.environ['DISCORD_WEBHOOK_URL']
    data = json.dumps(discord_payload).encode('utf-8')
    req  = urllib.request.Request(
        webhook_url, data=data,
        headers={'Content-Type': 'application/json'}
    )
    urllib.request.urlopen(req)
```

```hcl
# aws-shared-services-infra/discord_alerting.tf

resource "aws_sns_topic" "alerts" {
  name = "loadberry-alerts"
}

resource "aws_secretsmanager_secret" "discord_webhook" {
  name = "loadberry/discord-webhook-url"
}

resource "aws_lambda_function" "discord_alert" {
  function_name = "loadberry-discord-alert"
  runtime       = "python3.12"
  handler       = "handler.handler"
  role          = aws_iam_role.lambda_discord.arn
  filename      = "discord_alert.zip"

  environment {
    variables = {
      DISCORD_WEBHOOK_URL = aws_secretsmanager_secret_version.discord_webhook.secret_string
    }
  }
}

resource "aws_sns_topic_subscription" "discord" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.discord_alert.arn
}

resource "aws_lambda_permission" "sns" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.discord_alert.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.alerts.arn
}
```

---

## Phase 1 — Passive Logs (aws-sandbox-infra)

Always-on, write continuously, query only when needed.

### VPC Flow Logs → S3

```hcl
resource "aws_flow_log" "vpc" {
  vpc_id          = module.vpc.vpc_id
  traffic_type    = "ALL"
  iam_role_arn    = aws_iam_role.flow_log.arn
  log_destination = "${aws_s3_bucket.logs.arn}/vpc-flow-logs/"
  log_destination_type = "s3"

  tags = { Name = "sandbox-vpc-flow-logs" }
}

resource "aws_s3_bucket" "logs" {
  bucket = "loadberry-sandbox-logs-eu-west-2"
}

resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    id     = "expire-after-30-days"
    status = "Enabled"
    expiration { days = 30 }   # keep 30 days, then auto-delete — cost control
  }
}
```

### ALB Access Logs → S3

```hcl
# Add to alb.tf in aws-sandbox-infra
resource "aws_lb" "this" {
  ...
  access_logs {
    bucket  = aws_s3_bucket.logs.bucket
    prefix  = "alb-access-logs"
    enabled = true
  }
}
```

### RDS Logs → CloudWatch Logs

```hcl
# Add to rds.tf in aws-sandbox-infra
resource "aws_db_instance" "this" {
  ...
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  # Sends slow queries + errors to CloudWatch Logs automatically
}
```

---

## Phase 2 — CloudWatch Alarms → SNS → Discord (aws-sandbox-infra)

```hcl
locals {
  alert_sns_arn = "arn:aws:sns:eu-west-2:SHARED_SERVICES_ACCOUNT:loadberry-alerts"
}

# ALB: 5xx error rate > 5% for 5 minutes
resource "aws_cloudwatch_metric_alarm" "alb_5xx" {
  alarm_name          = "sandbox-alb-5xx-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "HTTPCode_Target_5XX_Count"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Sum"
  threshold           = 10
  alarm_actions       = [local.alert_sns_arn]
  ok_actions          = [local.alert_sns_arn]
  dimensions = { LoadBalancer = module.alb.arn_suffix }
}

# RDS: CPU > 80% for 10 minutes
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "sandbox-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = [local.alert_sns_arn]
  dimensions = { DBInstanceIdentifier = module.rds.db_instance_id }
}

# RDS: free storage < 5GB
resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "sandbox-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 5368709120   # 5GB in bytes
  alarm_actions       = [local.alert_sns_arn]
  dimensions = { DBInstanceIdentifier = module.rds.db_instance_id }
}

# EKS: node CPU > 85%
resource "aws_cloudwatch_metric_alarm" "eks_cpu" {
  alarm_name          = "sandbox-eks-node-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "node_cpu_utilization"
  namespace           = "ContainerInsights"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_actions       = [local.alert_sns_arn]
  dimensions = { ClusterName = "sandbox-cluster" }
}
```

---

## Phase 3 — EKS Container Insights (aws-sandbox-infra)

Fluent Bit DaemonSet ships pod logs + metrics to CloudWatch automatically.

```hcl
resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/containerinsights/sandbox-cluster/application"
  retention_in_days = 30
}

# Enable Container Insights on EKS cluster
resource "aws_eks_addon" "cloudwatch_observability" {
  cluster_name = module.eks.cluster_name
  addon_name   = "amazon-cloudwatch-observability"
  # Installs Fluent Bit + CloudWatch Agent automatically
}
```

What you get automatically:
- Pod logs (stdout/stderr from every container)
- CPU + memory per pod, per namespace, per node
- Pre-built Container Insights dashboard in CloudWatch console

---

## Phase 4 — Grafana Dashboard (aws-shared-services-infra)

```hcl
resource "aws_grafana_workspace" "this" {
  name                     = "loadberry-grafana"
  account_access_type      = "ORGANIZATION"
  authentication_providers = ["AWS_SSO"]   # login via your existing SSO
  permission_type          = "SERVICE_MANAGED"
  organizational_units     = [var.shared_ou_id]

  data_sources = ["CLOUDWATCH", "AMAZON_OPENSEARCH_SERVICE", "PROMETHEUS"]
}

# IAM role so Grafana can read CloudWatch across all accounts
resource "aws_grafana_workspace_iam_role_association" "cloudwatch" {
  role     = "VIEWER"
  user_ids = []   # managed via SSO groups
  workspace_id = aws_grafana_workspace.this.id
}
```

### Cross-account CloudWatch observability (aws-org-infra)

Allows Grafana in shared-services to read CloudWatch from sandbox and management:

```hcl
# In aws-org-infra/2-organisation/ — new file: cloudwatch_observability.tf

resource "aws_oam_sink" "monitoring" {
  name = "loadberry-monitoring-sink"
}

resource "aws_oam_sink_policy" "monitoring" {
  sink_identifier = aws_oam_sink.monitoring.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { "AWS" = var.org_arn }
      Action    = ["oam:CreateLink", "oam:UpdateLink"]
      Resource  = "*"
      Condition = {
        ForAllValues:StringEquals = {
          "oam:ResourceTypes" = [
            "AWS::CloudWatch::Metric",
            "AWS::Logs::LogGroup"
          ]
        }
      }
    }]
  })
}

# Link sandbox account as a source
resource "aws_oam_link" "sandbox" {
  label_template  = "$AccountName"
  resource_types  = ["AWS::CloudWatch::Metric", "AWS::Logs::LogGroup"]
  sink_identifier = aws_oam_sink.monitoring.arn

  provider = aws.sandbox
}
```

### Grafana dashboards to import (free, community)

After workspace is running, import these dashboard IDs:
- `17119` — AWS EKS cluster overview
- `650`   — AWS RDS overview
- `13659` — AWS ALB overview
- `11001` — VPC Flow Logs

---

## Cost Summary

| Resource | Monthly cost | Notes |
|---|---|---|
| VPC Flow Logs → S3 | ~$1-2 | 30-day retention |
| ALB access logs → S3 | ~$0.50 | Minimal at POC scale |
| RDS logs → CloudWatch | ~$1-2 | Retention 30 days |
| CloudWatch Alarms (4) | $0 | Within free tier (first 10) |
| SNS | $0 | Within free tier |
| Lambda (Discord) | $0 | Within free tier |
| Container Insights (EKS) | ~$9 | $0.0625/node/hr × 2 nodes |
| Grafana workspace | $0 | 90-day free trial |
| **Total** | **~$12-15/month** | |

---

## Repo Ownership

| What | Repo | File |
|---|---|---|
| SNS central topic | aws-shared-services-infra | `discord_alerting.tf` |
| Discord Lambda | aws-shared-services-infra | `discord_alerting.tf` + `discord_alert.py` |
| Grafana workspace | aws-shared-services-infra | `grafana.tf` |
| CloudWatch OAM sink | aws-org-infra/2-organisation | `cloudwatch_observability.tf` |
| VPC Flow Logs | aws-sandbox-infra | `vpc_logs.tf` |
| ALB access logs | aws-sandbox-infra | `alb.tf` (add access_logs block) |
| RDS logs | aws-sandbox-infra | `rds.tf` (add enabled_cloudwatch_logs_exports) |
| CloudWatch Alarms | aws-sandbox-infra | `alarms.tf` |
| Container Insights | aws-sandbox-infra | `eks.tf` (add addon) |

---

## Validation Checklist

- [ ] Discord #loadberry-aws-alerts channel receives test alarm
- [ ] VPC Flow Logs appear in S3 within 10 minutes of enabling
- [ ] ALB access logs appear in S3 after first HTTP request
- [ ] RDS logs appear in CloudWatch Logs group
- [ ] Container Insights shows pod CPU/memory in CloudWatch console
- [ ] Grafana workspace accessible via SSO login
- [ ] Grafana dashboard shows EKS + RDS + ALB metrics from sandbox
- [ ] Trigger test alarm manually → Discord notification received
