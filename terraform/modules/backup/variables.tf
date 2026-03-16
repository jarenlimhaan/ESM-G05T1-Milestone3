# ==============================================================================
# Backup Module Variables
# ==============================================================================
# Variables for configuring AWS Backup.

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Backup Targets

variable "odoo_rds_arn" {
  description = "ARN of the Odoo RDS instance"
  type        = string
}

variable "moodle_rds_arn" {
  description = "ARN of the Moodle RDS instance"
  type        = string
}

variable "efs_arn" {
  description = "ARN of the EFS file system"
  type        = string
}

# Backup Schedule

variable "backup_retention_days" {
  description = "Number of days to retain backups"
  type        = number
  default     = 14
}

variable "backup_schedule" {
  description = "Cron expression for backup schedule (UTC)"
  type        = string
  default     = "cron(0 3 * * ? *)" # Daily at 3 AM UTC
}

variable "backup_window" {
  description = "Time window for backup execution (UTC)"
  type        = string
  default     = "03:00-04:00"
}

# Common Tags

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
