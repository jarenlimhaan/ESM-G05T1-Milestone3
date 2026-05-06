output "aws_region" {
  description = "AWS region used by this stack"
  value       = var.aws_region
}

output "vpc_id" {
  description = "ID of the created VPC"
  value       = data.terraform_remote_state.lz1.outputs.vpc_id
}

output "vpc_cidr" {
  description = "CIDR block of the VPC"
  value       = data.terraform_remote_state.lz1.outputs.vpc_cidr
}

output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = data.terraform_remote_state.lz1.outputs.public_subnet_ids
}

output "private_app_subnet_ids" {
  description = "IDs of private application subnets"
  value       = data.terraform_remote_state.lz1.outputs.private_app_subnet_ids
}

output "private_db_subnet_ids" {
  description = "IDs of private database subnets"
  value       = data.terraform_remote_state.lz1.outputs.private_db_subnet_ids
}

output "nat_gateway_ids" {
  description = "IDs of NAT Gateways"
  value       = data.terraform_remote_state.lz1.outputs.nat_gateway_ids
}

output "nat_instance_id" {
  description = "ID of NAT instance (if enabled)"
  value       = data.terraform_remote_state.lz1.outputs.nat_instance_id
}

output "nat_instance_public_ip" {
  description = "Public IP of NAT instance (if enabled)"
  value       = data.terraform_remote_state.lz1.outputs.nat_instance_public_ip
}

output "internet_gateway_id" {
  description = "ID of the Internet Gateway"
  value       = data.terraform_remote_state.lz1.outputs.internet_gateway_id
}

output "eks_cluster_id" {
  description = "EKS Cluster ID"
  value       = module.eks.cluster_id
}

output "eks_cluster_name" {
  description = "EKS Cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "EKS Cluster API endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_security_group_id" {
  description = "Security group ID attached to the EKS cluster"
  value       = module.eks.cluster_security_group_id
}

output "eks_node_group_id" {
  description = "EKS Node Group ID"
  value       = module.eks.node_group_id
}

output "eks_cluster_autoscaler_role_arn" {
  description = "IAM role ARN for the Kubernetes Cluster Autoscaler"
  value       = module.eks.cluster_autoscaler_role_arn
}

output "eks_node_group_autoscaling_group_name" {
  description = "Auto Scaling Group name backing the EKS managed node group"
  value       = module.eks.node_group_autoscaling_group_name
}

output "eks_node_count_min" {
  description = "Minimum number of EKS worker nodes"
  value       = var.eks_node_count_min
}

output "eks_node_count_max" {
  description = "Maximum number of EKS worker nodes"
  value       = var.eks_node_count_max
}

output "public_alb_dns_name" {
  description = "DNS name of the public ALB"
  value       = module.alb_public.alb_dns_name
}

output "internal_alb_dns_name" {
  description = "DNS name of the internal ALB"
  value       = module.alb_internal.alb_dns_name
}

output "public_alb_zone_id" {
  description = "Zone ID of the public ALB"
  value       = module.alb_public.alb_zone_id
}

output "internal_alb_zone_id" {
  description = "Zone ID of the internal ALB"
  value       = module.alb_internal.alb_zone_id
}

output "public_alb_arn" {
  description = "ARN of the public ALB"
  value       = module.alb_public.alb_arn
}

output "internal_alb_arn" {
  description = "ARN of the internal ALB"
  value       = module.alb_internal.alb_arn
}

output "alb_dns_name" {
  description = "DNS name of the internal ALB (deprecated alias)"
  value       = module.alb_internal.alb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the internal ALB (deprecated alias)"
  value       = module.alb_internal.alb_zone_id
}

output "alb_arn" {
  description = "ARN of the internal ALB (deprecated alias)"
  value       = module.alb_internal.alb_arn
}

output "application_access_urls" {
  description = "Access URLs for applications"
  value = {
    odoo_public       = module.dns.odoo_public_fqdn != null ? "http://${module.dns.odoo_public_fqdn}" : "http://${module.alb_public.alb_dns_name}"
    odoo_internal     = module.dns.odoo_internal_fqdn != null ? "http://${module.dns.odoo_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/odoo"
    moodle_internal   = module.dns.moodle_internal_fqdn != null ? "http://${module.dns.moodle_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/moodle"
    osticket_internal = module.dns.osticket_internal_fqdn != null ? "http://${module.dns.osticket_internal_fqdn}/scp/" : "http://${module.alb_internal.alb_dns_name}/osticket/scp/"
  }
}

output "odoo_rds_endpoint" {
  description = "Endpoint of the Odoo PostgreSQL database"
  value       = module.rds.odoo_endpoint
  sensitive   = true
}

output "odoo_rds_port" {
  description = "Port of the Odoo PostgreSQL database"
  value       = module.rds.odoo_port
}

output "odoo_rds_instance_id" {
  description = "Instance ID of the Odoo PostgreSQL database"
  value       = module.rds.odoo_instance_id
}

output "odoo_db_name" {
  description = "Odoo database name"
  value       = var.odoo_db_name
}

output "moodle_rds_endpoint" {
  description = "Endpoint of the Moodle MySQL database"
  value       = module.rds.moodle_endpoint
  sensitive   = true
}

output "moodle_rds_port" {
  description = "Port of the Moodle MySQL database"
  value       = module.rds.moodle_port
}

output "moodle_rds_instance_id" {
  description = "Instance ID of the Moodle MySQL database"
  value       = module.rds.moodle_instance_id
}

output "efs_id" {
  description = "ID of the EFS file system"
  value       = module.efs.efs_id
}

output "efs_odoo_access_point_id" {
  description = "EFS access point ID used by Odoo"
  value       = module.efs.odoo_access_point_id
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = module.efs.efs_dns_name
}

output "efs_mount_target_ids" {
  description = "IDs of EFS mount targets"
  value       = module.efs.mount_target_ids
}

output "vpn_endpoint_id" {
  description = "ID of the VPN Client endpoint"
  value       = data.terraform_remote_state.lz1.outputs.vpn_endpoint_id
}

output "vpn_endpoint_dns" {
  description = "DNS name of the VPN Client endpoint"
  value       = data.terraform_remote_state.lz1.outputs.vpn_endpoint_dns
}

output "security_group_ids" {
  description = "Map of security group IDs"
  value       = data.terraform_remote_state.lz1.outputs.security_group_ids
}

output "backup_vault_arn" {
  description = "ARN of the AWS Backup vault"
  value       = module.backup.backup_vault_arn
}

output "backup_plan_id" {
  description = "ID of the backup plan"
  value       = module.backup.backup_plan_id
}

output "cloudwatch_log_group_arn" {
  description = "ARN of the CloudWatch log group for EKS"
  value       = module.eks.cloudwatch_log_group_arn
}

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = module.monitoring.sns_topic_arn
}

output "public_waf_web_acl_arn" {
  description = "ARN of the WAF Web ACL for the public ALB"
  value       = module.waf.web_acl_arn
}

output "route53_public_zone_id" {
  description = "Route 53 public hosted zone ID"
  value       = module.dns.public_zone_id
}

output "route53_private_zone_id" {
  description = "Route 53 private hosted zone ID"
  value       = module.dns.private_zone_id
}

output "odoo_public_dns_name" {
  description = "Route 53 DNS name for public Odoo"
  value       = module.dns.odoo_public_fqdn
}

output "odoo_internal_dns_name" {
  description = "Route 53 DNS name for internal Odoo"
  value       = module.dns.odoo_internal_fqdn
}

output "moodle_internal_dns_name" {
  description = "Route 53 DNS name for internal Moodle"
  value       = module.dns.moodle_internal_fqdn
}

output "osticket_internal_dns_name" {
  description = "Route 53 DNS name for internal osTicket"
  value       = module.dns.osticket_internal_fqdn
}

output "cloudtrail_arn" {
  description = "CloudTrail ARN"
  value       = try(data.terraform_remote_state.lz0.outputs.cloudtrail_arn, null)
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket used by CloudTrail"
  value       = try(data.terraform_remote_state.lz0.outputs.cloudtrail_s3_bucket, null)
}
