# Outputs are only available after the AFT module is applied.
# All blocks are commented out because the module is not applied in the POC.
#
# In production, these outputs are useful for:
#   - Referencing the AFT pipeline ARN in monitoring dashboards
#   - Passing the CodePipeline name to notification scripts
#   - Confirming which S3 bucket AFT uses for artefacts

# output "aft_pipeline_arn" {
#   description = "ARN of the CodePipeline that processes account requests"
#   value       = module.aft.codepipeline_arn
# }

# output "aft_account_provisioning_framework_arn" {
#   description = "ARN of the Step Functions state machine that orchestrates account vending"
#   value       = module.aft.account_provisioning_framework_arn
# }

# output "aft_s3_bucket" {
#   description = "S3 bucket used by AFT to store pipeline artefacts"
#   value       = module.aft.s3_bucket_name
# }

# output "aft_sns_topic_arn" {
#   description = "SNS topic ARN for AFT notifications (account vending complete)"
#   value       = module.aft.sns_topic_arn
# }
