# ==============================================================================
# ALB Module Variables
# ==============================================================================
# Variables for configuring Application Load Balancer.

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

variable "subnet_ids" {
  description = "Subnet IDs where the ALB will be deployed"
  type        = list(string)
}

# Security Group

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "internal" {
  description = "Whether ALB is internal (true) or internet-facing (false)"
  type        = bool
  default     = true
}

variable "alb_name_suffix" {
  description = "Suffix for ALB and target group names (for example: public, internal)"
  type        = string
  default     = "internal"
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
