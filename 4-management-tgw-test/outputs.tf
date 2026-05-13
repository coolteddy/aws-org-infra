output "vpc_id" {
  description = "Management TGW test VPC ID."
  value       = module.vpc.vpc_id
}

output "vpc_cidr_block" {
  description = "Management TGW test VPC CIDR block."
  value       = module.vpc.vpc_cidr_block
}

output "public_subnet_ids" {
  description = "Management TGW test public subnet IDs."
  value       = module.vpc.public_subnet_ids
}

output "tgw_attachment_id" {
  description = "Management TGW VPC attachment ID."
  value       = aws_ec2_transit_gateway_vpc_attachment.management.id
}

output "tgw_test_instance_id" {
  description = "Temporary management TGW test EC2 instance ID, or null when disabled."
  value       = var.create_tgw_test_instance ? module.tgw_test_ec2[0].instance_id : null
}

output "tgw_test_instance_private_ip" {
  description = "Temporary management TGW test EC2 private IP, or null when disabled."
  value       = var.create_tgw_test_instance ? module.tgw_test_ec2[0].private_ip : null
}

output "tgw_test_instance_public_ip" {
  description = "Temporary management TGW test EC2 public IP, or null when disabled."
  value       = var.create_tgw_test_instance ? module.tgw_test_ec2[0].public_ip : null
}
