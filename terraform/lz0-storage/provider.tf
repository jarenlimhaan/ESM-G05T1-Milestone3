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
