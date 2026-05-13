terraform {
  backend "s3" {
    bucket         = "loadberry-org-tf-state-eu-west-2"
    key            = "management-tgw-test/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "loadberry-org-tf-locks"
    encrypt        = true
  }
}
