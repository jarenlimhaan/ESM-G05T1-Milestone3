# ==============================================================================
# Terraform Outputs
# ==============================================================================
# Outputs provide important information after infrastructure deployment.

# ==============================================================================
# VPC Outputs
# ==============================================================================

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

# ==============================================================================
# EKS Outputs
# ==============================================================================

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

output "eks_config_command" {
  description = "Command to configure kubectl for the EKS cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

# ==============================================================================
# ALB Outputs
# ==============================================================================

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

# Backward-compatible aliases
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
    osticket_internal = module.dns.osticket_internal_fqdn != null ? "http://${module.dns.osticket_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/osticket"
  }
}

# ==============================================================================
# RDS Outputs
# ==============================================================================

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

# ==============================================================================
# EFS Outputs
# ==============================================================================

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

# ==============================================================================
# VPN Outputs
# ==============================================================================

output "vpn_endpoint_id" {
  description = "ID of the VPN Client endpoint"
  value       = module.vpn.vpn_endpoint_id
}

output "vpn_endpoint_dns" {
  description = "DNS name of the VPN Client endpoint"
  value       = module.vpn.vpn_endpoint_dns
}

output "vpn_connection_instructions" {
  description = "Instructions for connecting to the VPN"
  value       = <<EOT
To connect to the VPN:

1. Export the VPN client configuration using AWS CLI:
   aws ec2 export-client-vpn-client-configuration \
     --client-vpn-endpoint-id ${module.vpn.vpn_endpoint_id} \
     --output text > esm-vpn-config.ovpn

2. Open AWS VPN Client application

3. Import the .ovpn configuration file

4. Enter your VPN credentials when prompted

5. After connection, access applications:
   - Odoo Internal:  ${module.dns.odoo_internal_fqdn != null ? "http://${module.dns.odoo_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/odoo"}
   - Moodle Internal: ${module.dns.moodle_internal_fqdn != null ? "http://${module.dns.moodle_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/moodle"}
   - osTicket Internal: ${module.dns.osticket_internal_fqdn != null ? "http://${module.dns.osticket_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/osticket"}
EOT
}

# ==============================================================================
# Security Groups Outputs
# ==============================================================================

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

# ==============================================================================
# Backup Outputs
# ==============================================================================

output "backup_vault_arn" {
  description = "ARN of the AWS Backup vault"
  value       = module.backup.backup_vault_arn
}

output "backup_plan_id" {
  description = "ID of the backup plan"
  value       = module.backup.backup_plan_id
}

# ==============================================================================
# Monitoring Outputs
# ==============================================================================

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

# ==============================================================================
# DNS Outputs
# ==============================================================================

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

# ==============================================================================
# CloudTrail Outputs
# ==============================================================================

output "cloudtrail_arn" {
  description = "CloudTrail ARN"
  value       = module.cloudtrail.trail_arn
}

output "cloudtrail_s3_bucket" {
  description = "S3 bucket used by CloudTrail"
  value       = module.cloudtrail.s3_bucket_name
}

# ==============================================================================
# Summary Output
# ==============================================================================

output "deployment_summary" {
  description = "Summary of the deployed infrastructure"
  value       = <<EOT
================================================================================
                    ESM Enterprise Platform - Deployment Summary
================================================================================

Region: ${var.aws_region}
Environment: ${var.environment}

NETWORKING:
  VPC ID: ${module.vpc.vpc_id}
  VPC CIDR: ${module.vpc.vpc_cidr}
  Public Subnets: ${join(", ", module.vpc.public_subnet_ids)}
  Private App Subnets: ${join(", ", module.vpc.private_app_subnet_ids)}
  Private DB Subnets: ${join(", ", module.vpc.private_db_subnet_ids)}
  NAT Instance ID: ${coalesce(module.vpc.nat_instance_id, "disabled")}
  NAT Gateway IDs: ${length(module.vpc.nat_gateway_ids) > 0 ? join(", ", module.vpc.nat_gateway_ids) : "disabled"}

CONTAINER PLATFORM:
  EKS Cluster: ${module.eks.cluster_name}
  EKS Endpoint: ${module.eks.cluster_endpoint}
  Node Group: ${module.eks.node_group_id}

LOAD BALANCING:
  Public ALB DNS: ${module.alb_public.alb_dns_name}
  Internal ALB DNS: ${module.alb_internal.alb_dns_name}
  Odoo Public URL: ${module.dns.odoo_public_fqdn != null ? "http://${module.dns.odoo_public_fqdn}" : "http://${module.alb_public.alb_dns_name}"}
  Odoo Internal URL: ${module.dns.odoo_internal_fqdn != null ? "http://${module.dns.odoo_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/odoo"}
  Moodle Internal URL: ${module.dns.moodle_internal_fqdn != null ? "http://${module.dns.moodle_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/moodle"}
  osTicket Internal URL: ${module.dns.osticket_internal_fqdn != null ? "http://${module.dns.osticket_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/osticket"}
  Odoo Public DNS (Route53): ${coalesce(module.dns.odoo_public_fqdn, "not-configured")}
  Odoo Internal DNS (Route53): ${coalesce(module.dns.odoo_internal_fqdn, "not-configured")}
  Moodle Internal DNS (Route53): ${coalesce(module.dns.moodle_internal_fqdn, "not-configured")}
  osTicket Internal DNS (Route53): ${coalesce(module.dns.osticket_internal_fqdn, "not-configured")}

DATABASES:
  Odoo PostgreSQL: ${module.rds.odoo_endpoint} (Port ${module.rds.odoo_port})
  Moodle MySQL: ${module.rds.moodle_endpoint} (Port ${module.rds.moodle_port})

STORAGE:
  EFS ID: ${module.efs.efs_id}
  EFS DNS: ${module.efs.efs_dns_name}

VPN ACCESS:
  VPN Endpoint: ${module.vpn.vpn_endpoint_dns}
  Client CIDR: ${var.vpn_client_cidr}

BACKUP:
  Backup Vault: ${module.backup.backup_vault_arn}
  Retention: ${var.backup_retention_days} days

MONITORING:
  SNS Topic: ${module.monitoring.sns_topic_arn}
  Alert Email: ${var.alert_email}

AUDIT:
  CloudTrail ARN: ${coalesce(module.cloudtrail.trail_arn, "disabled")}
  CloudTrail Bucket: ${coalesce(module.cloudtrail.s3_bucket_name, "disabled")}

================================================================================
                              NEXT STEPS
================================================================================

1. CONNECT TO VPN:
   - Run: aws ec2 export-client-vpn-client-configuration --client-vpn-endpoint-id ${module.vpn.vpn_endpoint_id} --output text > vpn-config.ovpn
   - Open AWS VPN Client and import the configuration
   - Connect to access internal resources

2. CONFIGURE KUBECTL:
   - Run: aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}

3. VERIFY APPLICATIONS:
   - Check kubectl get pods -n esm
   - Access Odoo Public: ${module.dns.odoo_public_fqdn != null ? "http://${module.dns.odoo_public_fqdn}" : "http://${module.alb_public.alb_dns_name}"}
   - Access Odoo Internal: ${module.dns.odoo_internal_fqdn != null ? "http://${module.dns.odoo_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/odoo"}
   - Access Moodle Internal: ${module.dns.moodle_internal_fqdn != null ? "http://${module.dns.moodle_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/moodle"}
   - Access osTicket Internal: ${module.dns.osticket_internal_fqdn != null ? "http://${module.dns.osticket_internal_fqdn}" : "http://${module.alb_internal.alb_dns_name}/osticket"}

4. VERIFY BACKUPS:
   - Navigate to AWS Backup console
   - Check backup jobs and vault status

================================================================================
EOT
}

output "aws_region" {
  description = "AWS region used by this stack"
  value       = var.aws_region
}
