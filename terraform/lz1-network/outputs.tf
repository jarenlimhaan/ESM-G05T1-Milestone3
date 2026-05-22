output "aws_region" {
  description = "AWS region used by this stack"
  value       = var.aws_region
}

output "vpc_id" {
  description = "ID of the created VPC"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = module.vpc.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "IDs of private application subnets"
  value       = module.vpc.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "IDs of private database subnets"
  value       = module.vpc.private_db_subnet_ids
}

output "nat_gateway_ids" {
  description = "IDs of NAT Gateways"
  value       = module.vpc.nat_gateway_ids
}

output "nat_instance_id" {
  description = "ID of NAT instance (if enabled)"
  value       = module.vpc.nat_instance_id
}

output "nat_instance_public_ip" {
  description = "Public IP of NAT instance (if enabled)"
  value       = module.vpc.nat_instance_public_ip
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = module.vpc.internet_gateway_id
}

output "security_group_ids" {
  description = "Map of security group IDs"
  value = {
    public_alb   = module.security_groups.public_alb_sg_id
    internal_alb = module.security_groups.internal_alb_sg_id
    eks_nodes    = module.security_groups.eks_nodes_sg_id
    eks_cluster  = module.security_groups.eks_cluster_sg_id
    odoo_rds     = module.security_groups.odoo_rds_sg_id
    moodle_rds   = module.security_groups.moodle_rds_sg_id
    efs          = module.security_groups.efs_sg_id
    vpn          = module.security_groups.vpn_sg_id
  }
}

output "vpn_endpoint_id" {
  description = "ID of the VPN Client endpoint"
  value       = module.vpn.vpn_endpoint_id
}

output "vpn_endpoint_dns" {
  description = "DNS name of the VPN Client endpoint"
  value       = module.vpn.vpn_endpoint_dns
}
