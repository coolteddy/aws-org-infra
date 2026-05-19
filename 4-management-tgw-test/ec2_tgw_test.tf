# data "aws_ami" "al2023" {
#   count = var.create_tgw_test_instance ? 1 : 0

#   most_recent = true
#   owners      = ["amazon"]

#   filter {
#     name   = "name"
#     values = ["al2023-ami-2023*-x86_64"]
#   }

#   filter {
#     name   = "architecture"
#     values = ["x86_64"]
#   }

#   filter {
#     name   = "virtualization-type"
#     values = ["hvm"]
#   }
# }

# module "tgw_test_ec2" {
#   count = var.create_tgw_test_instance ? 1 : 0

#   source = "git::https://github.com/coolteddy/aws-terraform-modules.git//modules/ec2?ref=v1.0.0"

#   name          = "management-tgw-test"
#   vpc_id        = module.vpc.vpc_id
#   subnet_id     = module.vpc.public_subnet_ids[0]
#   ami_id        = data.aws_ami.al2023[0].id
#   instance_type = "t3.nano"

#   ingress_ports     = []
#   create_elastic_ip = true

#   tags = {
#     Component = "tgw-test"
#     Temporary = "true"
#   }
# }

# resource "aws_vpc_security_group_ingress_rule" "tgw_test_icmp" {
#   count = var.create_tgw_test_instance ? 1 : 0

#   security_group_id = module.tgw_test_ec2[0].security_group_id
#   description       = "ICMP from private RFC1918 TGW test CIDRs"
#   from_port         = -1
#   to_port           = -1
#   ip_protocol       = "icmp"
#   cidr_ipv4         = "10.0.0.0/8"

#   tags = {
#     Name      = "management-tgw-test-icmp"
#     Component = "tgw-test"
#     Temporary = "true"
#   }
# }
