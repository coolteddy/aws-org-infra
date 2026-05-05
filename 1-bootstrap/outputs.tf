output "state_bucket_name" {
  description = "Name of the S3 bucket for Terraform remote state — use this in backend.tf for layers 2 and 3"
  value       = aws_s3_bucket.tf_state.id
}

output "state_bucket_arn" {
  description = "ARN of the S3 bucket — used when granting the GitHub Actions role access to state"
  value       = aws_s3_bucket.tf_state.arn
}

output "lock_table_name" {
  description = "Name of the DynamoDB lock table — use this in backend.tf for layers 2 and 3"
  value       = aws_dynamodb_table.tf_locks.name
}

output "lock_table_arn" {
  description = "ARN of the DynamoDB lock table"
  value       = aws_dynamodb_table.tf_locks.arn
}

output "region" {
  description = "AWS region where bootstrap resources were created"
  value       = var.region
}
