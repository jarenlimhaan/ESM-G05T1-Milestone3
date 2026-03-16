# ==============================================================================
# Security Groups Module Variables
# ==============================================================================
# Variables for configuring security groups with least-privilege access.

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID for security groups"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block for intra-VPC communication"
  type        = string
}

variable "vpn_client_cidr" {
  description = "CIDR block for VPN clients"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
