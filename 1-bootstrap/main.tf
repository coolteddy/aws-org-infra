terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # No backend block here — bootstrap uses local state intentionally.
  # This layer creates the S3 bucket that all other layers use as their backend.
  # You cannot store state in a bucket that doesn't exist yet.
  # After apply, the local terraform.tfstate file is kept on your machine only.
}

provider "aws" {
  region = var.region
}

# ------------------------------------------------------------------------------
# S3 bucket — remote state storage for layers 2 and 3
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "tf_state" {
  bucket = var.state_bucket_name

  # prevent_destroy stops `terraform destroy` from deleting this bucket.
  # Losing this bucket means losing all Terraform state — unrecoverable.
  lifecycle {
    prevent_destroy = true
  }

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# DynamoDB table — state locking
# Prevents two terraform apply runs from colliding and corrupting state.
# LockID is the partition key name Terraform requires — do not change it.
# ------------------------------------------------------------------------------

resource "aws_dynamodb_table" "tf_locks" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = var.tags
}
