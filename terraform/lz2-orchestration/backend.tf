terraform {
  backend "s3" {
    bucket         = "esm-enterprise-prod-tf-state-jar"
    key            = "prod/lz2-orchestration.tfstate"
    region         = "ap-southeast-1"
    dynamodb_table = "esm-enterprise-prod-tf-lock"
    encrypt        = true
  }
}
