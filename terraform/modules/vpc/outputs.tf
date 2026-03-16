# ==============================================================================
# VPC Module Outputs
# ==============================================================================
# Outputs from the VPC module for use by other modules.

output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "IDs of private application subnets"
  value       = aws_subnet.private_app[*].id
}

output "private_db_subnet_ids" {
  description = "IDs of private database subnets"
  value       = aws_subnet.private_db[*].id
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = aws_internet_gateway.main.id
}

output "nat_gateway_ids" {
  description = "IDs of NAT Gateways"
  value       = aws_nat_gateway.main[*].id
}

output "public_route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}

output "private_app_route_table_id" {
  description = "ID of the private application route table"
  value       = aws_route_table.private_app.id
}

output "private_db_route_table_id" {
  description = "ID of the private database route table"
  value       = aws_route_table.private_db.id
}

output "vpc_main_route_table_id" {
  description = "ID of the VPC main route table"
  value       = aws_vpc.main.main_route_table_id
}

output "vpc_endpoint_security_group_id" {
  description = "Security group ID used by interface VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

output "interface_vpc_endpoint_ids" {
  description = "Interface VPC endpoint IDs"
  value       = [for endpoint in aws_vpc_endpoint.interface : endpoint.id]
}

output "s3_vpc_endpoint_id" {
  description = "S3 gateway VPC endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}
