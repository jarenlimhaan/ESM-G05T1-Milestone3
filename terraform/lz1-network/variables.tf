variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "esm-enterprise"
}

variable "environment" {
  description = "Environment name"
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

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "List of availability zones to use"
  type        = list(string)
  default     = ["ap-southeast-1a", "ap-southeast-1b"]
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for public subnets"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_app_subnet_cidrs" {
  description = "CIDR blocks for private application subnets"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "private_db_subnet_cidrs" {
  description = "CIDR blocks for private database subnets"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

variable "use_nat_instance" {
  description = "Use NAT instance for private subnet outbound internet access"
  type        = bool
  default     = true
}

variable "vpn_client_cidr" {
  description = "CIDR block for VPN clients"
  type        = string
  default     = "10.100.0.0/16"
}

variable "vpn_server_certificate_arn" {
  description = "ARN of the ACM certificate for VPN server"
  type        = string
  default     = ""
}

variable "public_alb_allowed_cidrs" {
  description = "CIDR blocks that can access the public ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
