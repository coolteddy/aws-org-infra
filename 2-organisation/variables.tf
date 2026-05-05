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

variable "tags" {
  description = "Tags applied to all resources in this layer"
  type        = map(string)
  default = {
    Project     = "aws-org-infra"
    ManagedBy   = "terraform"
    Environment = "management"
  }
}
