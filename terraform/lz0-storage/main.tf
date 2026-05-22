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

module "cloudtrail" {
  source = "../modules/cloudtrail"

  project_name      = var.project_name
  environment       = var.environment
  enable_cloudtrail = var.enable_cloudtrail
  common_tags       = local.common_tags
}
