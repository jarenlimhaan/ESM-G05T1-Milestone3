# ==============================================================================
# Main Terraform Configuration
# ==============================================================================
# This is the entry point for the ESM Enterprise Platform infrastructure.
# It orchestrates all modules to create a complete, secure enterprise platform.

# ==============================================================================
# Locals
# ==============================================================================
# Define common values and tags that are used across modules.

locals {
  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    },
    var.additional_tags
  )

  project_prefix = "${var.project_name}-${var.environment}"
}

# ==============================================================================
# Module: VPC
# ==============================================================================
# Creates the foundational networking infrastructure including VPC, subnets,
# route tables, Internet Gateway, and NAT Gateway.

module "vpc" {
  source = "./modules/vpc"

  project_name       = var.project_name
  environment        = var.environment
  vpc_cidr           = var.vpc_cidr
  availability_zones = var.availability_zones
  # Use a single public subnet for a single NAT Gateway (cost-optimized).
  # Both private AZs route outbound traffic through this NAT.
  public_subnet_cidrs = slice(var.public_subnet_cidrs, 0, 1)

  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs

  enable_nat_gateway = true
  single_nat_gateway = true
  aws_region         = var.aws_region

  common_tags = local.common_tags
}

# ==============================================================================
# Module: Security Groups
# ==============================================================================
# Creates all security groups with least-privilege access rules.
# Depends on VPC module for VPC ID and subnet information.

module "security_groups" {
  source = "./modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr

  vpn_client_cidr = var.vpn_client_cidr

  common_tags = local.common_tags
}

# ==============================================================================
# Module: RDS (Databases)
# ==============================================================================
# Creates PostgreSQL for Odoo and MySQL for Moodle in private subnets.
# Depends on VPC for subnet groups and Security Groups for access rules.

module "rds" {
  source = "./modules/rds"

  project_name = var.project_name
  environment  = var.environment

  # VPC Configuration
  vpc_id             = module.vpc.vpc_id
  availability_zones = var.availability_zones
  private_subnet_ids = module.vpc.private_db_subnet_ids

  # Security Groups
  odoo_security_group_id   = module.security_groups.odoo_rds_sg_id
  moodle_security_group_id = module.security_groups.moodle_rds_sg_id

  # Odoo PostgreSQL Configuration
  odoo_db_name        = var.odoo_db_name
  odoo_db_username    = var.odoo_db_username
  odoo_db_password    = var.odoo_db_password
  odoo_instance_class = var.db_instance_class

  # Moodle MySQL Configuration
  moodle_db_name        = var.moodle_db_name
  moodle_db_username    = var.moodle_db_username
  moodle_db_password    = var.moodle_db_password
  moodle_instance_class = var.db_instance_class

  # Backup Configuration
  backup_retention_period = var.backup_retention_days

  common_tags = local.common_tags
}

# ==============================================================================
# Module: EFS (File Storage)
# ==============================================================================
# Creates EFS file system for Odoo persistent storage.
# Depends on VPC for subnets and Security Groups for NFS access.

module "efs" {
  source = "./modules/efs"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.vpc.vpc_id
  availability_zones = var.availability_zones
  private_subnet_ids = module.vpc.private_app_subnet_ids

  security_group_id = module.security_groups.efs_sg_id

  common_tags = local.common_tags
}

# ==============================================================================
# Module: Backup
# ==============================================================================
# Creates AWS Backup vault and plan for automated backups.
# Backs up RDS databases and EFS file system.

module "backup" {
  source = "./modules/backup"

  project_name = var.project_name
  environment  = var.environment

  # Backup Targets
  odoo_rds_arn   = module.rds.odoo_instance_arn
  moodle_rds_arn = module.rds.moodle_instance_arn
  efs_arn        = module.efs.efs_arn

  # Backup Schedule
  backup_retention_days = var.backup_retention_days

  common_tags = local.common_tags

  depends_on = [
    module.rds,
    module.efs
  ]
}

# ==============================================================================
# Module: Monitoring
# ==============================================================================
# Creates CloudWatch Log Groups, Alarms, and SNS topic for alerts.

module "monitoring" {
  source = "./modules/monitoring"

  project_name = var.project_name
  environment  = var.environment

  alert_email = var.alert_email

  # Resources to monitor
  odoo_rds_id   = module.rds.odoo_instance_id
  moodle_rds_id = module.rds.moodle_instance_id
  efs_id        = module.efs.efs_id

  enable_monitoring = var.enable_monitoring

  common_tags = local.common_tags
}

# ==============================================================================
# Module: EKS (Kubernetes)
# ==============================================================================
# Creates EKS cluster with managed node group in private subnets.
# Depends on VPC for subnets and Security Groups for cluster access.

module "eks" {
  source = "./modules/eks"

  project_name = var.project_name
  environment  = var.environment

  # EKS Configuration
  cluster_version = var.eks_cluster_version
  cluster_name    = "${local.project_prefix}-eks"

  # VPC Configuration
  vpc_id             = module.vpc.vpc_id
  availability_zones = var.availability_zones
  private_subnet_ids = module.vpc.private_app_subnet_ids

  # Security Groups
  cluster_security_group_id = module.security_groups.eks_cluster_sg_id
  nodes_security_group_id   = module.security_groups.eks_nodes_sg_id

  # Node Group Configuration
  node_instance_type = var.eks_node_instance_type
  node_count_min     = var.eks_node_count_min
  node_count_max     = var.eks_node_count_max
  node_count_desired = var.eks_node_count_desired

  # Monitoring
  enable_cloudwatch_logging = var.enable_monitoring

  common_tags = local.common_tags
}

# ==============================================================================
# Module: ALB (Application Load Balancer)
# ==============================================================================
# Creates internal ALB for routing traffic to Kubernetes services.
# Depends on VPC for subnets and Security Groups for HTTP access.

module "alb" {
  source = "./modules/alb"

  project_name = var.project_name
  environment  = var.environment

  # VPC Configuration
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_app_subnet_ids

  # Security Groups
  alb_security_group_id = module.security_groups.alb_sg_id

  # Certificate
  certificate_arn = var.alb_certificate_arn

  common_tags = local.common_tags

  depends_on = [module.eks]
}

# ==============================================================================
# Module: VPN (Client VPN)
# ==============================================================================
# Creates AWS Client VPN endpoint for secure internal access.
# Depends on VPC for subnets and Security Groups for VPN access.

module "vpn" {
  source = "./modules/vpn"

  project_name = var.project_name
  environment  = var.environment

  # VPC Configuration
  vpc_id             = module.vpc.vpc_id
  availability_zones = var.availability_zones
  private_subnet_ids = module.vpc.private_app_subnet_ids

  # VPN Configuration
  vpn_client_cidr        = var.vpn_client_cidr
  server_certificate_arn = var.vpn_server_certificate_arn

  # Security Groups
  vpn_security_group_id = module.security_groups.vpn_sg_id

  common_tags = local.common_tags
}

# ==============================================================================
# Kubernetes Workloads
# ==============================================================================
# App workloads are intentionally deployed outside Terraform.
# Apply manifests from the repository's /k8s directory with kubectl after
# infrastructure provisioning completes.
