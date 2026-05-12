variable "region" {
  description = "AWS region for the management plane"
  type        = string
  default     = "eu-west-2"
}

variable "management_account_id" {
  description = "AWS management account ID — used in the GitHub OIDC role trust policy"
  type        = string
  # no default — must be provided via terraform.tfvars (gitignored)
}

variable "github_org" {
  description = "GitHub organisation or username that owns this repo — scopes the OIDC trust"
  type        = string
  # no default — must be provided via terraform.tfvars (gitignored)
}

variable "github_repo" {
  description = "GitHub repository name — restricts OIDC trust to this repo only"
  type        = string
  default     = "aws-org-infra"
}

variable "github_shared_services_repo" {
  description = "GitHub repository name for shared-services Terraform"
  type        = string
  default     = "aws-shared-services-infra"
}

variable "github_sandbox_repo" {
  description = "GitHub repository name for sandbox Terraform"
  type        = string
  default     = "aws-sandbox-infra"
}

variable "shared_services_account_id" {
  description = "AWS account ID for shared-services — used by the GitHub OIDC gateway role"
  type        = string
  sensitive   = true
  # no default — must be provided via terraform.tfvars or GitHub Actions variables/secrets
}

variable "sandbox_email" {
  description = "Unique email address for the sandbox account (use a Gmail alias e.g. you+aws-sandbox@gmail.com)"
  type        = string
  sensitive   = true
  # no default - passed via GitHub Secret SANDBOX_EMAIL in CI/CD
  # locally: add to terraform.tfvars (gitignored)
}

variable "tags" {
  description = "Tags applied to all resources in this layer"
  type        = map(string)
  default = {
    Project     = "aws-org-infra"
    ManagedBy   = "terraform"
    Environment = "management"
  }
}
