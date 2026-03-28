# ==============================================================================
# Main Terraform Configuration
# ==============================================================================
# This is the entry point for the ESM Enterprise Platform infrastructure.
# It orchestrates all modules to create a complete, secure enterprise platform.

# ==============================================================================
# Locals
# ==============================================================================
# Define common values and tags that are used across modules.

# ==============================================================================
# Secrets Manager — Terraform owns and creates all secrets
# ==============================================================================

resource "aws_secretsmanager_secret" "odoo_db_password" {
  name                    = var.odoo_db_password_secret_id
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "odoo_db_password" {
  secret_id     = aws_secretsmanager_secret.odoo_db_password.id
  secret_string = var.odoo_db_password
}

resource "aws_secretsmanager_secret" "moodle_db_password" {
  name                    = var.moodle_db_password_secret_id
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "moodle_db_password" {
  secret_id     = aws_secretsmanager_secret.moodle_db_password.id
  secret_string = var.moodle_db_password
}

resource "aws_secretsmanager_secret" "osticket_db_password" {
  name                    = var.osticket_db_password_secret_id
  recovery_window_in_days = 0
  tags                    = local.common_tags
}

resource "aws_secretsmanager_secret_version" "osticket_db_password" {
  secret_id     = aws_secretsmanager_secret.osticket_db_password.id
  secret_string = var.osticket_db_password
}

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

  has_public_zone_name  = trimspace(var.public_route53_zone_name) != ""
  has_private_zone_name = trimspace(var.private_route53_zone_name) != ""

  use_public_host_routing   = var.create_public_route53_zone && local.has_public_zone_name
  use_internal_host_routing = var.create_private_route53_zone && local.has_private_zone_name

  odoo_public_fqdn = "${var.odoo_public_record_name}.${var.public_route53_zone_name}"

  odoo_internal_fqdn     = "${var.odoo_internal_record_name}.${var.private_route53_zone_name}"
  moodle_internal_fqdn   = "${var.moodle_internal_record_name}.${var.private_route53_zone_name}"
  osticket_internal_fqdn = "${var.osticket_internal_record_name}.${var.private_route53_zone_name}"

  odoo_db_password_resolved   = aws_secretsmanager_secret_version.odoo_db_password.secret_string
  moodle_db_password_resolved = aws_secretsmanager_secret_version.moodle_db_password.secret_string
}

# ==============================================================================
# Module: VPC
# ==============================================================================
# Creates the foundational networking infrastructure including VPC, subnets,
# route tables, Internet Gateway, and NAT Gateway.

module "vpc" {
  source = "./modules/vpc"

  project_name        = var.project_name
  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
  public_subnet_cidrs = var.public_subnet_cidrs

  private_app_subnet_cidrs = var.private_app_subnet_cidrs
  private_db_subnet_cidrs  = var.private_db_subnet_cidrs

  enable_nat_gateway = !var.use_nat_instance
  single_nat_gateway = true
  use_nat_instance   = var.use_nat_instance
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

  vpn_client_cidr          = var.vpn_client_cidr
  public_alb_allowed_cidrs = var.public_alb_allowed_cidrs

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
  odoo_db_password    = local.odoo_db_password_resolved
  odoo_instance_class = var.db_instance_class

  # Moodle MySQL Configuration
  moodle_db_name        = var.moodle_db_name
  moodle_db_username    = var.moodle_db_username
  moodle_db_password    = local.moodle_db_password_resolved
  moodle_instance_class = var.db_instance_class

  # Backup Configuration
  backup_retention_period           = var.backup_retention_days
  automated_backup_retention_period = var.rds_automated_backup_retention_period
  skip_final_snapshot               = var.rds_skip_final_snapshot

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
# Module: Public ALB (Application Load Balancer)
# ==============================================================================
# Creates internet-facing ALB for public workloads.
# Depends on VPC for subnets and Security Groups for HTTP access.

module "alb_public" {
  source = "./modules/alb"

  project_name = var.project_name
  environment  = var.environment

  # VPC Configuration
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.public_subnet_ids

  # Security Groups
  alb_security_group_id = module.security_groups.public_alb_sg_id

  # Public LB
  internal            = false
  alb_name_suffix     = "public"
  node_group_asg_name = module.eks.node_group_autoscaling_group_name
  odoo_node_port      = 30080
  odoo_path_patterns  = ["/*"]
  odoo_host_headers   = local.use_public_host_routing ? [local.odoo_public_fqdn] : []
  enable_odoo         = true
  enable_moodle       = false
  enable_osticket     = false

  # Certificate
  certificate_arn = var.alb_certificate_arn

  common_tags = local.common_tags

  depends_on = [module.eks]
}

# ==============================================================================
# Module: Internal ALB (Application Load Balancer)
# ==============================================================================
# Creates internal ALB for VPN-only workloads.

module "alb_internal" {
  source = "./modules/alb"

  project_name = var.project_name
  environment  = var.environment

  # VPC Configuration
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_app_subnet_ids

  # Security Groups
  alb_security_group_id = module.security_groups.internal_alb_sg_id

  # Internal LB
  internal               = true
  alb_name_suffix        = "internal"
  node_group_asg_name    = module.eks.node_group_autoscaling_group_name
  odoo_node_port         = 30081
  odoo_path_patterns     = local.use_internal_host_routing ? ["/*"] : ["/odoo*", "/web*"]
  odoo_host_headers      = local.use_internal_host_routing ? [local.odoo_internal_fqdn] : []
  moodle_node_port       = 30082
  moodle_path_patterns   = local.use_internal_host_routing ? ["/*"] : ["/moodle*"]
  moodle_host_headers    = local.use_internal_host_routing ? [local.moodle_internal_fqdn] : []
  osticket_node_port     = 30083
  osticket_path_patterns = local.use_internal_host_routing ? ["/*"] : ["/osticket*"]
  osticket_host_headers  = local.use_internal_host_routing ? [local.osticket_internal_fqdn] : []
  enable_odoo            = true
  enable_moodle          = true
  enable_osticket        = true

  # Certificate
  certificate_arn = var.alb_certificate_arn

  common_tags = local.common_tags

  depends_on = [module.eks]
}

# ==============================================================================
# Module: WAF
# ==============================================================================
# Protect public ALB with managed and rate-limiting rules.

module "waf" {
  source = "./modules/waf"

  project_name = var.project_name
  environment  = var.environment

  enable_waf     = var.enable_waf
  waf_rate_limit = var.waf_rate_limit
  alb_public_arn = module.alb_public.alb_arn
  common_tags    = local.common_tags

  depends_on = [module.alb_public]
}

# ==============================================================================
# Module: DNS (Route 53)
# ==============================================================================
# Creates optional public and private hosted zones plus ALB alias records.

module "dns" {
  source = "./modules/dns"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id

  create_public_zone  = var.create_public_route53_zone
  public_zone_name    = var.public_route53_zone_name
  create_private_zone = var.create_private_route53_zone
  private_zone_name   = var.private_route53_zone_name

  odoo_public_record_name       = var.odoo_public_record_name
  odoo_internal_record_name     = var.odoo_internal_record_name
  moodle_internal_record_name   = var.moodle_internal_record_name
  osticket_internal_record_name = var.osticket_internal_record_name

  public_alb_dns_name   = module.alb_public.alb_dns_name
  public_alb_zone_id    = module.alb_public.alb_zone_id
  internal_alb_dns_name = module.alb_internal.alb_dns_name
  internal_alb_zone_id  = module.alb_internal.alb_zone_id

  common_tags = local.common_tags

  depends_on = [module.alb_public, module.alb_internal]
}

# ==============================================================================
# Module: CloudTrail
# ==============================================================================
# Captures AWS API audit logs to S3 and CloudWatch.

module "cloudtrail" {
  source = "./modules/cloudtrail"

  project_name = var.project_name
  environment  = var.environment

  enable_cloudtrail = var.enable_cloudtrail

  common_tags = local.common_tags
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
# Kubernetes Secrets Bridge
# ==============================================================================
# Terraform reads the EKS cluster credentials and pushes secrets directly into
# the appropriate namespaces. This replaces the placeholder substitution in
# deploy-k8s-apps.sh for all password/secret values.

data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority)
  token                  = data.aws_eks_cluster_auth.main.token
}

# Namespaces — Terraform creates them so secrets can be placed immediately.
# kubectl apply -k will no-op on these since they already exist.

resource "kubernetes_namespace" "odoo_public" {
  metadata {
    name = "odoo-public"
    labels = { "app.kubernetes.io/part-of" = "esm" }
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "odoo_private" {
  metadata {
    name = "odoo-private"
    labels = { "app.kubernetes.io/part-of" = "esm" }
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "moodle_private" {
  metadata {
    name = "moodle-private"
    labels = { "app.kubernetes.io/part-of" = "esm" }
  }
  depends_on = [module.eks]
}

resource "kubernetes_namespace" "osticket_private" {
  metadata {
    name = "osticket-private"
    labels = { "app.kubernetes.io/part-of" = "esm" }
  }
  depends_on = [module.eks]
}

resource "kubernetes_secret" "odoo_db_odoo_public" {
  metadata {
    name      = "odoo-db"
    namespace = kubernetes_namespace.odoo_public.metadata[0].name
  }
  data = {
    password = aws_secretsmanager_secret_version.odoo_db_password.secret_string
  }
}

resource "kubernetes_secret" "odoo_db_odoo_private" {
  metadata {
    name      = "odoo-db"
    namespace = kubernetes_namespace.odoo_private.metadata[0].name
  }
  data = {
    password = aws_secretsmanager_secret_version.odoo_db_password.secret_string
  }
}

resource "kubernetes_secret" "moodle_db" {
  metadata {
    name      = "moodle-db"
    namespace = kubernetes_namespace.moodle_private.metadata[0].name
  }
  data = {
    password = aws_secretsmanager_secret_version.moodle_db_password.secret_string
  }
}

resource "kubernetes_secret" "osticket_db" {
  metadata {
    name      = "osticket-db"
    namespace = kubernetes_namespace.osticket_private.metadata[0].name
  }
  data = {
    password       = aws_secretsmanager_secret_version.osticket_db_password.secret_string
    install_secret = var.osticket_install_secret
    admin_password = var.osticket_admin_password
  }
}

