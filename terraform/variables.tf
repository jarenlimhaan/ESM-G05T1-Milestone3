# ==============================================================================
# Project Variables
# ==============================================================================
# Centralized configuration variables for the entire infrastructure.

variable "project_name" {
  description = "Name of the project, used for resource naming"
  type        = string
  default     = "esm-enterprise"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod"
  }
}

variable "owner" {
  description = "Owner/Team responsible for the infrastructure"
  type        = string
  default     = "ESM-Team"
}

# ==============================================================================
# AWS Configuration
# ==============================================================================

variable "aws_region" {
  description = "AWS region for deployment (Asia Pacific for data residency)"
  type        = string
  default     = "ap-southeast-1"
}

# ==============================================================================
# VPC Networking
# ==============================================================================

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

# ==============================================================================
# VPN Configuration
# ==============================================================================

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

# Note: For production, you must create an ACM certificate first:
# aws acm request-certificate --domain-name vpn.esm.local --validation-method DNS

# ==============================================================================
# EKS Configuration
# ==============================================================================

variable "eks_cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.29"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.medium"
}

variable "eks_node_count_min" {
  description = "Minimum number of EKS nodes"
  type        = number
  default     = 2
}

variable "eks_node_count_max" {
  description = "Maximum number of EKS nodes"
  type        = number
  default     = 5
}

variable "eks_node_count_desired" {
  description = "Desired number of EKS nodes"
  type        = number
  default     = 2
}

# ==============================================================================
# Database Configuration
# ==============================================================================

variable "odoo_db_name" {
  description = "Name of the Odoo PostgreSQL database"
  type        = string
  default     = "odoodb"
}

variable "odoo_db_username" {
  description = "Username for Odoo PostgreSQL database"
  type        = string
  default     = "odoo_admin"
  sensitive   = true
}

variable "odoo_db_password" {
  description = "Password for Odoo PostgreSQL database"
  type        = string
  default     = "ChangeMeSecurePassword123!"
  sensitive   = true
}

variable "moodle_db_name" {
  description = "Name of the Moodle MySQL database"
  type        = string
  default     = "moodledb"
}

variable "moodle_db_username" {
  description = "Username for Moodle MySQL database"
  type        = string
  default     = "moodle_admin"
  sensitive   = true
}

variable "moodle_db_password" {
  description = "Password for Moodle MySQL database"
  type        = string
  default     = "ChangeMeSecurePassword456!"
  sensitive   = true
}

variable "db_instance_class" {
  description = "RDS instance class for databases"
  type        = string
  default     = "db.t3.small"
}

# ==============================================================================
# Backup Configuration
# ==============================================================================

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 14
}

variable "rds_automated_backup_retention_period" {
  description = "RDS automated backup retention days (set 0 to rely on AWS Backup only)"
  type        = number
  default     = 0
}

variable "rds_skip_final_snapshot" {
  description = "Skip final snapshot on RDS deletion"
  type        = bool
  default     = true
}

# ==============================================================================
# ALB Configuration
# ==============================================================================

variable "alb_certificate_arn" {
  description = "ARN of the ACM certificate for ALB (optional)"
  type        = string
  default     = ""
}

variable "public_alb_allowed_cidrs" {
  description = "CIDR blocks that can access the public ALB"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_waf" {
  description = "Enable WAF on public ALB"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Per-IP rate limit (5-minute window) for AWS WAF rate-based rule"
  type        = number
  default     = 2000
}

# ==============================================================================
# DNS Configuration
# ==============================================================================

variable "create_public_route53_zone" {
  description = "Create public Route 53 hosted zone and records for public ALB"
  type        = bool
  default     = false
}

variable "public_route53_zone_name" {
  description = "Public Route 53 hosted zone name (for example, example.com)"
  type        = string
  default     = ""
}

variable "create_private_route53_zone" {
  description = "Create private Route 53 hosted zone and records for internal ALB"
  type        = bool
  default     = true
}

variable "private_route53_zone_name" {
  description = "Private Route 53 hosted zone name (for example, internal.esm.local)"
  type        = string
  default     = "internal.esm.local"
}

variable "odoo_public_record_name" {
  description = "Record prefix for public Odoo endpoint"
  type        = string
  default     = "odoo"
}

variable "odoo_internal_record_name" {
  description = "Record prefix for internal Odoo endpoint"
  type        = string
  default     = "odoo"
}

variable "moodle_internal_record_name" {
  description = "Record prefix for internal Moodle endpoint"
  type        = string
  default     = "moodle"
}

variable "osticket_internal_record_name" {
  description = "Record prefix for internal osTicket endpoint"
  type        = string
  default     = "osticket"
}

# ==============================================================================
# Audit Configuration
# ==============================================================================

variable "enable_cloudtrail" {
  description = "Enable AWS CloudTrail for audit logging"
  type        = bool
  default     = true
}

# ==============================================================================
# Monitoring Configuration
# ==============================================================================

variable "enable_monitoring" {
  description = "Enable detailed CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

variable "alert_email" {
  description = "Email address for receiving alerts"
  type        = string
  default     = "jarenlim100@gmail.com"
}

# ==============================================================================
# Tags
# ==============================================================================

variable "additional_tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
