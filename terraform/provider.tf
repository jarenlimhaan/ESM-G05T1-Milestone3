# ==============================================================================
# AWS Provider Configuration
# ==============================================================================
# Configures the AWS provider with default region and tags.

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "ESM-Enterprise-Platform"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = var.owner
    }
  }
}
