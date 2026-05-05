variable "region" {
  description = "AWS region for all bootstrap resources"
  type        = string
  default     = "eu-west-2"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket that stores Terraform remote state for all layers"
  type        = string
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table used for Terraform state locking"
  type        = string
}

variable "tags" {
  description = "Tags applied to all bootstrap resources"
  type        = map(string)
  default = {
    Project     = "aws-org-infra"
    ManagedBy   = "terraform"
    Environment = "management"
  }
}
