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

output "eks_config_command" {
  description = "Command to configure kubectl for the EKS cluster"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.aws_region}"
}

# ==============================================================================
# ALB Outputs
# ==============================================================================

output "alb_dns_name" {
  description = "DNS name of the internal ALB"
  value       = module.alb.alb_dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB"
  value       = module.alb.alb_zone_id
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = module.alb.alb_arn
}

output "alb_access_urls" {
  description = "Access URLs for applications (after VPN connection)"
  value = {
    odoo   = "http://${module.alb.alb_dns_name}/odoo"
    moodle = "http://${module.alb.alb_dns_name}/moodle"
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
   - Odoo:   http://${module.alb.alb_dns_name}/odoo
   - Moodle: http://${module.alb.alb_dns_name}/moodle
EOT
}

# ==============================================================================
# Security Groups Outputs
# ==============================================================================

output "security_group_ids" {
  description = "Map of security group IDs"
  value = {
    alb         = module.security_groups.alb_sg_id
    eks_nodes   = module.security_groups.eks_nodes_sg_id
    eks_cluster = module.security_groups.eks_cluster_sg_id
    odoo_rds    = module.security_groups.odoo_rds_sg_id
    moodle_rds  = module.security_groups.moodle_rds_sg_id
    efs         = module.security_groups.efs_sg_id
    vpn         = module.security_groups.vpn_sg_id
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

CONTAINER PLATFORM:
  EKS Cluster: ${module.eks.cluster_name}
  EKS Endpoint: ${module.eks.cluster_endpoint}
  Node Group: ${module.eks.node_group_id}

LOAD BALANCING:
  ALB DNS: ${module.alb.alb_dns_name}
  Odoo URL: http://${module.alb.alb_dns_name}/odoo
  Moodle URL: http://${module.alb.alb_dns_name}/moodle

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
   - Access Odoo: http://${module.alb.alb_dns_name}/odoo
   - Access Moodle: http://${module.alb.alb_dns_name}/moodle

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
