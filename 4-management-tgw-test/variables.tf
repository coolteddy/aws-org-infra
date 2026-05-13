variable "region" {
  description = "AWS region for the management TGW test resources."
  type        = string
  default     = "eu-west-2"
}

variable "tgw_id" {
  description = "Shared-services Transit Gateway ID. Pass this from the shared-services stack output."
  type        = string
}

variable "shared_services_vpc_cidr" {
  description = "Shared-services VPC CIDR used for TGW routing."
  type        = string
  default     = "10.1.0.0/16"
}

variable "sandbox_vpc_cidr" {
  description = "Sandbox VPC CIDR used for TGW routing."
  type        = string
  default     = "10.2.0.0/16"
}

variable "create_tgw_test_instance" {
  description = "Create the temporary management EC2 instance for TGW connectivity testing."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Default tags applied to management TGW test resources."
  type        = map(string)
  default = {
    Project     = "aws-org-infra"
    ManagedBy   = "terraform"
    Environment = "management"
    Temporary   = "true"
  }
}
