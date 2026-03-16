# ==============================================================================
# EFS Module Variables
# ==============================================================================
# Variables for configuring EFS file system.

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

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "IDs of private application subnets"
  type        = list(string)
}

# Security Group

variable "security_group_id" {
  description = "Security group ID for EFS"
  type        = string
}

# Common Tags

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
