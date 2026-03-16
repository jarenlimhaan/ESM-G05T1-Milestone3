# ==============================================================================
# Monitoring Module Variables
# ==============================================================================
# Variables for configuring CloudWatch monitoring and alerts.

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Alert Configuration

variable "alert_email" {
  description = "Email address for receiving alerts"
  type        = string
}

# Resources to Monitor

variable "odoo_rds_id" {
  description = "Instance ID of Odoo RDS"
  type        = string
}

variable "moodle_rds_id" {
  description = "Instance ID of Moodle RDS"
  type        = string
}

variable "efs_id" {
  description = "ID of EFS file system"
  type        = string
}

# Monitoring Configuration

variable "enable_monitoring" {
  description = "Enable detailed CloudWatch monitoring and alarms"
  type        = bool
  default     = true
}

# Common Tags

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
