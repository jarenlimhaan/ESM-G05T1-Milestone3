# ==============================================================================
# RDS Module Variables
# ==============================================================================
# Variables for configuring RDS databases.

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
  description = "IDs of private database subnets"
  type        = list(string)
}

# Security Groups

variable "odoo_security_group_id" {
  description = "Security group ID for Odoo RDS"
  type        = string
}

variable "moodle_security_group_id" {
  description = "Security group ID for Moodle RDS"
  type        = string
}

# Odoo PostgreSQL Configuration

variable "odoo_db_name" {
  description = "Database name for Odoo"
  type        = string
}

variable "odoo_db_username" {
  description = "Database username for Odoo"
  type        = string
  sensitive   = true
}

variable "odoo_db_password" {
  description = "Database password for Odoo"
  type        = string
  sensitive   = true
}

variable "odoo_instance_class" {
  description = "Instance class for Odoo RDS"
  type        = string
  default     = "db.t3.micro"
}

# Moodle MySQL Configuration

variable "moodle_db_name" {
  description = "Database name for Moodle"
  type        = string
}

variable "moodle_db_username" {
  description = "Database username for Moodle"
  type        = string
  sensitive   = true
}

variable "moodle_db_password" {
  description = "Database password for Moodle"
  type        = string
  sensitive   = true
}

variable "moodle_instance_class" {
  description = "Instance class for Moodle RDS"
  type        = string
  default     = "db.t3.small"
}

# Backup Configuration

variable "backup_retention_period" {
  description = "Backup retention period in days"
  type        = number
}

variable "automated_backup_retention_period" {
  description = "RDS automated backup retention period in days (0 disables automated RDS backups)"
  type        = number
  default     = 0
}

variable "skip_final_snapshot" {
  description = "Skip final snapshot when deleting RDS instances"
  type        = bool
  default     = true
}

variable "backup_window" {
  description = "Preferred backup window in UTC"
  type        = string
  default     = "03:00-04:00"
}

variable "maintenance_window" {
  description = "Preferred maintenance window"
  type        = string
  default     = "Mon:04:00-Mon:05:00"
}

# Common Tags

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
