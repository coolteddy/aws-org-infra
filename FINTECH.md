# FinTech Plan — Financial Services Compliance

**FinTech compliance = proving to regulators and enterprise customers that your platform is secure, auditable, and resilient.**
This is not optional if you want to process payments, handle financial data, or sell to banks/insurers.

> **Status: post-testing** — implement after TGW test + security baseline + FinOps are in place.

---

## FinOps vs FinTech — the difference

| | FinOps | FinTech |
|---|---|---|
| **Focus** | Cost management | Compliance and regulation |
| **Who cares** | Engineers, co-founders, finance | Regulators, auditors, enterprise customers |
| **Goal** | Spend less, spend smarter | Pass audits, avoid fines, win enterprise deals |
| **File** | `FINOPS.md` | This file |

You need both. FinOps keeps your runway longer. FinTech compliance unlocks the customers who pay the most.

---

## Compliance Frameworks That Matter

### PCI DSS (Payment Card Industry Data Security Standard)
**Required when:** you store, process, or transmit credit/debit card data.
**Who enforces it:** card networks (Visa, Mastercard) via your payment processor.
**Consequence of failure:** fines, loss of ability to accept card payments.

Key requirements mapped to AWS:
| PCI DSS Requirement | AWS Control | Your Status |
|---|---|---|
| Network segmentation (Req 1) | VPC per tenant, TGW isolated routing | ✅ Planned |
| No default credentials (Req 2) | SSO only, no IAM users (SCP enforced) | ✅ Done |
| Encryption in transit (Req 4) | ALB HTTPS, TLS on RDS | Planned |
| Audit log all access (Req 10) | CloudTrail org trail → log-archive | ✅ Planned |
| Immutable logs (Req 10.5) | S3 Object Lock on log-archive | ✅ Planned |
| Restrict internet access (Req 1.3) | VPC Endpoints, no public RDS | Gap |
| Vulnerability management (Req 6) | AWS Inspector | Gap |
| Encrypt cardholder data (Req 3) | KMS Customer Managed Keys | Gap |

---

### SOC 2 Type II
**Required when:** selling B2B SaaS to enterprise customers — they will ask for your SOC 2 report.
**Who enforces it:** AICPA. Audited by a certified CPA firm over 6–12 months.
**Consequence of failure:** losing enterprise deals. Most companies >$50k ARR per customer require it.

Five Trust Service Criteria:
| Criteria | What auditors check | AWS Control |
|---|---|---|
| Security (CC6) | Access controls, encryption, monitoring | GuardDuty, Security Hub, KMS |
| Availability (A1) | Uptime, backups, multi-AZ | RDS Multi-AZ, ALB health checks |
| Confidentiality (C1) | Data classification, encryption at rest | Macie, KMS CMKs |
| Processing Integrity (PI1) | Data processed completely and accurately | CloudTrail, Config |
| Privacy (P1–P8) | PII handling, consent, retention | Macie, S3 lifecycle rules |

SOC 2 is largely an evidence collection exercise. CloudTrail + Security Hub + Config provide most of the evidence automatically.

---

### GDPR / UK GDPR
**Required when:** handling personal data of EU or UK residents (virtually all SaaS).
**Who enforces it:** ICO (UK), national DPAs (EU). Fines up to 4% of global annual revenue.

Key requirements:
| GDPR Article | Requirement | AWS Control |
|---|---|---|
| Art 5(1)(f) | Data integrity and confidentiality | KMS encryption, S3 bucket policies |
| Art 17 | Right to erasure | S3 Object Expiry, RDS delete + snapshot purge |
| Art 25 | Privacy by design | VPC private subnets, no public RDS/S3 |
| Art 32 | Encryption + pseudonymisation | KMS CMKs, RDS encryption |
| Art 33 | Breach notification within 72hrs | GuardDuty → SNS → PagerDuty/Slack |
| Art 44 | Data transfer restrictions | Region SCP (eu-west-2 only) ✅ Done |

---

### FCA (UK Financial Conduct Authority)
**Required when:** providing regulated financial services in the UK (lending, payments, investment).
**Key rules:** PS21/3 (Operational Resilience), SYSC (Systems and Controls).

Key requirements:
| FCA Rule | Requirement | AWS Control |
|---|---|---|
| Operational resilience | Recover important business services within impact tolerances | Multi-AZ RDS, ALB health checks, EKS self-healing |
| Outsourcing controls | Audit trail of third-party (AWS) access | CloudTrail, Config |
| Incident management | Detect, report, and remediate security incidents | GuardDuty, Security Hub, SNS alerts |
| Record-keeping | Retain records for defined periods | S3 Object Lock, RDS automated backups |

---

## What Your Current Structure Already Satisfies

| Requirement | Control in place |
|---|---|
| Data residency (GDPR Art 44) | Region SCP — eu-west-2 only ✅ |
| Immutable audit trail (PCI Req 10.5) | log-archive S3 Object Lock ✅ |
| No shared credentials (PCI Req 2) | SSO only, DenyIAMUserCreation SCP ✅ |
| Security monitoring disabled prevention | DenySecurityMonitoringDisable SCP ✅ |
| Tenant network isolation (PCI Req 1) | TGW isolated route tables ✅ |
| Public S3 blocked (GDPR Art 25) | DenyPublicS3 SCP ✅ |
| Threat detection (SOC 2 CC7) | GuardDuty → audit account ✅ Planned |
| Compliance monitoring (SOC 2 CC6) | Security Hub CIS benchmarks ✅ Planned |
| Resource change tracking | Config recorder → log-archive ✅ Planned |

---

## Gaps — What Needs to Be Added

### Gap 1 — KMS Customer Managed Keys
**Frameworks:** PCI DSS Req 3, GDPR Art 32, SOC 2 C1

Encrypt RDS, S3, and Secrets Manager with keys YOU control (not AWS-managed).
You can prove to auditors: key rotation happened on this date, this IAM role accessed the key.

```hcl
# Add kms_key_id to rds and s3 modules
resource "aws_kms_key" "rds" {
  description             = "RDS encryption key — tenant-a"
  deletion_window_in_days = 30
  enable_key_rotation     = true   # auto-rotates annually
  tags = { tenant = "tenant-a" }
}
```

Cost: $1/key/month + $0.03/10k API calls. Negligible.

---

### Gap 2 — VPC Endpoints
**Frameworks:** PCI DSS Req 1.3 (no internet for cardholder data)

RDS, Secrets Manager, S3, ECR traffic currently leaves VPC via internet gateway or NAT Gateway.
VPC Endpoints route this traffic on the AWS backbone — never touches the internet.

```hcl
# Add to vpc module as enable_vpc_endpoints toggle
# Endpoints needed: s3, secretsmanager, ecr.api, ecr.dkr, rds, ssm, ssmmessages
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.eu-west-2.s3"
  vpc_endpoint_type = "Gateway"   # free
}

resource "aws_vpc_endpoint" "secretsmanager" {
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.eu-west-2.secretsmanager"
  vpc_endpoint_type   = "Interface"   # $0.01/hr per AZ
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.endpoints.id]
}
```

Cost: Gateway endpoints (S3, DynamoDB) are free. Interface endpoints ~$7/month each.

---

### Gap 3 — Amazon Macie
**Frameworks:** GDPR Art 32, SOC 2 C1 (confidentiality), PCI DSS Req 3

Automatically scans S3 buckets for PII: credit card numbers, passport numbers, NHS numbers, email addresses.
Findings appear in Security Hub automatically.

```hcl
resource "aws_macie2_account" "sandbox" {
  provider = aws.sandbox
  status   = "ENABLED"
}

resource "aws_macie2_classification_job" "s3_scan" {
  provider   = aws.sandbox
  job_type   = "SCHEDULED"
  name       = "sandbox-pii-scan"
  schedule_frequency { weekly_schedule = "MONDAY" }
  s3_job_definition {
    bucket_definitions { account_id = var.sandbox_account_id, buckets = ["*"] }
  }
}
```

Cost: $1/GB of S3 data scanned + $0.001/S3 object. First 30 days free.

---

### Gap 4 — AWS Inspector
**Frameworks:** PCI DSS Req 6 (vulnerability management), SOC 2 CC7

Continuously scans EC2 instances, ECS containers, and Lambda functions for known CVEs.
Findings appear in Security Hub automatically.

```hcl
resource "aws_inspector2_enabler" "sandbox" {
  account_ids    = [var.sandbox_account_id]
  resource_types = ["EC2", "ECR", "LAMBDA"]
}
```

Cost: $0.11/EC2 instance/month, $0.09/container image scan. Free trial 15 days.

---

### Gap 5 — WAF (Web Application Firewall)
**Frameworks:** PCI DSS Req 6.4, SOC 2 CC6

Protects ALB and CloudFront from OWASP Top 10 attacks: SQL injection, XSS, path traversal.
Attach to ALB in aws-sandbox-infra.

```hcl
resource "aws_wafv2_web_acl" "alb" {
  name  = "sandbox-alb-waf"
  scope = "REGIONAL"

  default_action { allow {} }

  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config { cloudwatch_metrics_enabled = true, metric_name = "CommonRuleSet", sampled_requests_enabled = true }
  }
}
```

Cost: $5/month per WAF + $1/million requests. Negligible at POC scale.

---

## Implementation Plan (in order, post-testing)

### Phase 1 — Foundations (~2 days, low cost)
1. Activate Cost Allocation Tags in Billing console
2. Enable Macie in sandbox account (30-day free trial)
3. Enable Inspector in sandbox account (15-day free trial)
4. Add `enable_key_rotation = true` to any KMS keys already in use

### Phase 2 — Encryption (~1 week)
1. Add KMS CMK module or resource to aws-sandbox-infra
2. Update RDS module to accept `kms_key_id` variable (v1.1.0)
3. Update S3 module to accept `kms_key_id` variable (v1.1.0)
4. Re-encrypt existing sandbox RDS snapshot with new CMK

### Phase 3 — Network Hardening (~1 week)
1. Add VPC Endpoints to vpc module as `enable_vpc_endpoints` toggle
2. Deploy in sandbox — test ECR pulls + Secrets Manager access still work
3. Remove NAT Gateway from sandbox if all traffic moves to endpoints

### Phase 4 — WAF + Shield (~1 day)
1. Add WAF ACL resource to aws-sandbox-infra, attach to ALB
2. Enable AWS Shield Standard (free, auto-enabled — just verify it's on)

### Phase 5 — SOC 2 Readiness (~1 month of evidence collection)
1. Ensure CloudTrail, Config, GuardDuty, Security Hub all running for 30+ days
2. Export Security Hub findings report — this becomes SOC 2 evidence
3. Engage a SOC 2 auditor (e.g. Drata or Vanta automate evidence collection)

---

## Tools That Automate SOC 2 Evidence Collection

When you're ready for the audit:

| Tool | What it does | Cost |
|---|---|---|
| **Vanta** | Connects to AWS, GitHub, Slack. Automatically collects evidence. Generates SOC 2 report. | ~$800/month |
| **Drata** | Same as Vanta — continuous compliance monitoring | ~$800/month |
| **Sprinto** | Cheaper alternative, good for startups | ~$500/month |
| **Manual** | Export CloudTrail, Security Hub, Config reports yourself | Free but painful |

Vanta/Drata are worth it when you have a real enterprise customer asking for the SOC 2 report.
Before that: keep the AWS controls running and the evidence accumulates automatically.

---

## Files to Create (when implementing)

| File | Repo | What |
|---|---|---|
| `kms.tf` | aws-sandbox-infra | CMKs for RDS + S3 |
| `macie.tf` | aws-sandbox-infra | Macie classification jobs |
| `inspector.tf` | aws-sandbox-infra | Inspector enabler |
| `waf.tf` | aws-sandbox-infra | WAF ACL + ALB attachment |
| VPC endpoint resources | aws-terraform-modules vpc module | `enable_vpc_endpoints` toggle (v1.1.0) |
| `kms_key_id` variable | aws-terraform-modules rds + s3 modules | v1.1.0 improvement |
