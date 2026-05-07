# ==============================================================================
# Remote Backend Configuration
# ==============================================================================
# Add this file AFTER running terraform-bootstrap/ successfully.
# Then run: terraform init -migrate-state
# ==============================================================================

terraform {
  backend "s3" {
    bucket       = "esm-enterprise-prod-tf-state"
    key          = "prod/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
