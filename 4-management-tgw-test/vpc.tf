module "vpc" {
  source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/vpc?ref=v1.0.0"

  name       = "management-tgw-test"
  cidr_block = "10.0.0.0/16"

  public_subnets = {
    "eu-west-2a" = "10.0.0.0/24"
  }

  private_subnets = {}

  enable_nat_gateway = false

  tags = {
    Component = "tgw-test"
    Temporary = "true"
  }
}
