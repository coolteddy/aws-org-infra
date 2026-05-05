variable "region" {
  description = "AWS region where AFT pipeline runs — must match Control Tower home region"
  type        = string
  default     = "eu-west-2"
}

variable "management_account_id" {
  description = "AWS management account ID — where AFT pipeline is deployed"
  type        = string
  # no default — must be provided via terraform.tfvars (gitignored)
}

variable "log_archive_account_id" {
  description = "Account ID of the log-archive account created by Control Tower"
  type        = string
  # Created automatically when Control Tower is enrolled.
  # Find it in: AWS Organizations → Accounts → log-archive
  # no default — must be provided via terraform.tfvars (gitignored)
}

variable "audit_account_id" {
  description = "Account ID of the audit account created by Control Tower"
  type        = string
  # Created automatically when Control Tower is enrolled.
  # Find it in: AWS Organizations → Accounts → audit
  # no default — must be provided via terraform.tfvars (gitignored)
}

variable "github_org" {
  description = "GitHub organisation or username that owns the repos AFT watches"
  type        = string
  # no default — must be provided via terraform.tfvars (gitignored)
}

variable "admin_email" {
  description = "Email address for the SSO admin user in vended accounts"
  type        = string
  sensitive   = true
  # no default — must be provided via terraform.tfvars (gitignored)
  # This email receives the account invitation and is the initial SSO user.
}

variable "log_archive_email" {
  description = "Unique email address for the log-archive account"
  type        = string
  sensitive   = true
  # AWS requires a unique email per account — cannot reuse existing emails.
  # Convention: aws+logarchive@yourdomain.com
}

variable "audit_email" {
  description = "Unique email address for the audit account"
  type        = string
  sensitive   = true
  # Convention: aws+audit@yourdomain.com
}

variable "shared_services_email" {
  description = "Unique email address for the shared-services account"
  type        = string
  sensitive   = true
  # Convention: aws+sharedservices@yourdomain.com
}

variable "tags" {
  description = "Tags applied to all AFT resources"
  type        = map(string)
  default = {
    Project     = "aws-org-infra"
    ManagedBy   = "terraform"
    Environment = "management"
  }
}
