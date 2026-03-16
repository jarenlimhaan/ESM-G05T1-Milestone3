# ==============================================================================
# RDS Module Outputs
# ==============================================================================
# Outputs for RDS database information.

# Odoo PostgreSQL Outputs

output "odoo_instance_id" {
  description = "Instance ID of Odoo PostgreSQL"
  value       = aws_db_instance.odoo.id
}

output "odoo_instance_arn" {
  description = "ARN of Odoo PostgreSQL instance"
  value       = aws_db_instance.odoo.arn
}

output "odoo_endpoint" {
  description = "Endpoint of Odoo PostgreSQL"
  value       = aws_db_instance.odoo.endpoint
}

output "odoo_port" {
  description = "Port of Odoo PostgreSQL"
  value       = aws_db_instance.odoo.port
}

output "odoo_db_username" {
  description = "Database username for Odoo"
  value       = aws_db_instance.odoo.username
  sensitive   = true
}

output "odoo_db_password" {
  description = "Database password for Odoo"
  value       = var.odoo_db_password
  sensitive   = true
}

# Moodle MySQL Outputs

output "moodle_instance_id" {
  description = "Instance ID of Moodle MySQL"
  value       = aws_db_instance.moodle.id
}

output "moodle_instance_arn" {
  description = "ARN of Moodle MySQL instance"
  value       = aws_db_instance.moodle.arn
}

output "moodle_endpoint" {
  description = "Endpoint of Moodle MySQL"
  value       = aws_db_instance.moodle.endpoint
}

output "moodle_port" {
  description = "Port of Moodle MySQL"
  value       = aws_db_instance.moodle.port
}

output "moodle_db_username" {
  description = "Database username for Moodle"
  value       = aws_db_instance.moodle.username
  sensitive   = true
}

output "moodle_db_password" {
  description = "Database password for Moodle"
  value       = var.moodle_db_password
  sensitive   = true
}

# Subnet Group Outputs

output "db_subnet_group_id" {
  description = "ID of the DB subnet group"
  value       = aws_db_subnet_group.main.id
}
