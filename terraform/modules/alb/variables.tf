# ==============================================================================
# ALB Module Variables
# ==============================================================================
# Variables for configuring internal Application Load Balancer.

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# VPC Configuration

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "IDs of private application subnets"
  type        = list(string)
}

# Security Group

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

# Certificate

variable "certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS"
  type        = string
  default     = ""
}

# Common Tags

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
