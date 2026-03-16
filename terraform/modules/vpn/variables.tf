# ==============================================================================
# VPN Module Variables
# ==============================================================================
# Variables for configuring AWS Client VPN.

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

# VPN Configuration

variable "vpn_client_cidr" {
  description = "CIDR block for VPN clients"
  type        = string
}

variable "server_certificate_arn" {
  description = "ARN of the ACM certificate for VPN server"
  type        = string
  default     = ""
}

# Security Group

variable "vpn_security_group_id" {
  description = "Security group ID for VPN"
  type        = string
}

# Common Tags

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
