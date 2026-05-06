variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "esm-enterprise"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "owner" {
  description = "Owner/Team responsible for the infrastructure"
  type        = string
  default     = "ESM-Team"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "ap-southeast-1"
}

variable "enable_cloudtrail" {
  description = "Enable AWS CloudTrail for audit logging"
  type        = bool
  default     = true
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
