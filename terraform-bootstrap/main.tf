# ==============================================================================
# Phase 0 — Remote State Backend Bootstrap
# ==============================================================================
# Run this ONCE before using terraform/ for the first time.
# Creates the S3 bucket and DynamoDB table that will hold Terraform state.
#
# Steps:
#   1. cd terraform-bootstrap
#   2. terraform init
#   3. terraform apply
#   4. cd ../terraform
#   5. terraform init -migrate-state
# ==============================================================================

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "ap-southeast-1"
}

# ------------------------------------------------------------------------------
# S3 Bucket — stores the .tfstate file
# ------------------------------------------------------------------------------
resource "aws_s3_bucket" "tf_state" {
  bucket = "esm-enterprise-prod-tf-state-jar"

  # Prevent accidental deletion via terraform destroy
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# DynamoDB Table — provides state locking (prevents concurrent applies)
# ------------------------------------------------------------------------------
resource "aws_dynamodb_table" "tf_lock" {
  name         = "esm-enterprise-prod-tf-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

# ------------------------------------------------------------------------------
# Outputs — copy these into terraform/backend.tf
# ------------------------------------------------------------------------------
output "state_bucket_name" {
  value = aws_s3_bucket.tf_state.bucket
}

output "lock_table_name" {
  value = aws_dynamodb_table.tf_lock.name
}
