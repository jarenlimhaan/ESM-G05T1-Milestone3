# ==============================================================================
# Terraform Version Constraints
# ==============================================================================
# This file defines the required Terraform and provider versions for the project.
# Terraform 1.5+ is required for AWS provider 5.x compatibility.

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }

    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    time = {
      source  = "hashicorp/time"
      version = "~> 0.12"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.31"
    }
  }

  # ==============================================================================
  # Terraform State Backend
  # ==============================================================================
  # For production use, configure a remote backend (S3 + DynamoDB)
  # Uncomment and configure the following block:

  # backend "s3" {
  #   bucket         = "esm-terraform-state"
  #   key            = "prod/terraform.tfstate"
  #   region         = "ap-southeast-1"
  #   encrypt        = true
  #   dynamodb_table = "esm-terraform-locks"
  # }
}
