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
}

module "vpc" {
  source = "../modules/vpc"

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

module "security_groups" {
  source = "../modules/security"

  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.vpc.vpc_id
  vpc_cidr     = module.vpc.vpc_cidr

  vpn_client_cidr          = var.vpn_client_cidr
  public_alb_allowed_cidrs = var.public_alb_allowed_cidrs

  common_tags = local.common_tags
}

module "vpn" {
  source = "../modules/vpn"

  project_name = var.project_name
  environment  = var.environment

  vpc_id             = module.vpc.vpc_id
  availability_zones = var.availability_zones
  private_subnet_ids = module.vpc.private_app_subnet_ids

  vpn_client_cidr        = var.vpn_client_cidr
  server_certificate_arn = var.vpn_server_certificate_arn

  vpn_security_group_id = module.security_groups.vpn_sg_id

  common_tags = local.common_tags
}
