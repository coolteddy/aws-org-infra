# Layer 1 — Bootstrap

This layer runs **once only**, locally, using a temporary IAM user. It creates the S3 bucket and DynamoDB table that all other layers use for remote Terraform state.

## Why a Separate Bootstrap Layer

Layers 2 and 3 store their Terraform state in an S3 bucket. That bucket must exist before those layers can run — which means something has to create it first. The bootstrap layer creates it using local state, then is never touched again.

```
Bootstrap creates S3 bucket + DynamoDB
        ↓
Layer 2 (organisation) stores its state in that bucket
        ↓
Layer 3 (AFT) stores its state in that bucket
        ↓
GitHub Actions uses that bucket for all future applies
```

## Prerequisites

Before running bootstrap you need a temporary IAM user (`org-bootstrap`) with permissions to create S3 and DynamoDB resources. This user is deleted after SSO is configured.

```
AWS Console → IAM → Users → Create user
Name: org-bootstrap
Permissions: AmazonS3FullAccess + AmazonDynamoDBFullAccess
Access type: Programmatic (access key + secret)
```

Configure the CLI profile:
```bash
aws configure --profile org-bootstrap
# Enter: Access Key ID, Secret Access Key, region: eu-west-2
```

## Running Bootstrap

```bash
# 1. Set the profile
export AWS_PROFILE=org-bootstrap

# 2. Enter the bootstrap directory
cd 1-bootstrap/

# 3. Copy the example vars file and fill in real values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your bucket and table names

# 4. Initialise — downloads the AWS provider locally
terraform init

# 5. Review what will be created
terraform plan

# 6. Create the resources
terraform apply
```

## What Gets Created

| Resource | Purpose |
|----------|---------|
| S3 bucket | Stores Terraform state files for all layers. Versioning + encryption enabled. |
| DynamoDB table | Locks state during `terraform apply` — prevents two applies running simultaneously. |

## After Bootstrap

The local `terraform.tfstate` file stays on your machine only — never commit it. It can be safely discarded after bootstrap since the resources it tracks (S3 + DynamoDB) are permanent and protected by `prevent_destroy`.

## Tools and Versions

| Tool | Version |
|------|---------|
| Terraform | >= 1.6.0 |
| AWS Provider | ~> 5.0 |
| AWS CLI | v2 (latest) |
