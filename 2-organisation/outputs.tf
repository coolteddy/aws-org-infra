output "organisation_id" {
  description = "The AWS Organisation ID"
  value       = data.aws_organizations_organization.this.id
  sensitive   = true
}

output "root_id" {
  description = "The Organisation Root ID — used to attach SCPs at the org level"
  value       = data.aws_organizations_organization.this.roots[0].id
  sensitive   = true
}

output "security_ou_id" {
  description = "Security OU ID — for placing log-archive and audit accounts"
  value       = aws_organizations_organizational_unit.security.id
  sensitive   = true
}

output "shared_ou_id" {
  description = "Shared OU ID — for placing shared-services account"
  value       = aws_organizations_organizational_unit.shared.id
  sensitive   = true
}

output "workloads_ou_id" {
  description = "Workloads OU ID — parent of all tenant OUs"
  value       = aws_organizations_organizational_unit.workloads.id
  sensitive   = true
}

output "tenant_a_ou_id" {
  description = "Tenant-A OU ID — parent of all Tenant-A accounts"
  value       = aws_organizations_organizational_unit.tenant_a.id
  sensitive   = true
}

output "github_actions_role_arn" {
  description = "ARN of the GitHub Actions IAM role for aws-org-infra — paste this into your workflow files"
  value       = aws_iam_role.github_aws_org_infra.arn
  sensitive   = true
}

output "sso_instance_arn" {
  description = "IAM Identity Center instance ARN — needed when adding user assignments"
  value       = local.sso_instance_arn
  sensitive   = true
}
