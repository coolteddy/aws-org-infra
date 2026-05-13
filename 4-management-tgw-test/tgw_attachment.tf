locals {
  tgw_routes = {
    shared_services = var.shared_services_vpc_cidr
    sandbox         = var.sandbox_vpc_cidr
  }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "management" {
  transit_gateway_id = var.tgw_id
  vpc_id             = module.vpc.vpc_id
  subnet_ids         = module.vpc.public_subnet_ids

  tags = {
    Name      = "management-tgw-test-attachment"
    Component = "tgw-test"
    Temporary = "true"
  }
}

resource "aws_route" "public_to_tgw" {
  for_each = local.tgw_routes

  route_table_id         = module.vpc.public_route_table_id
  destination_cidr_block = each.value
  transit_gateway_id     = var.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.management]
}
