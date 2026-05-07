# ==============================================================================
# EFS Module Outputs
# ==============================================================================
# Outputs for EFS file system information.

output "efs_id" {
  description = "ID of the EFS file system"
  value       = aws_efs_file_system.main.id
}

output "efs_arn" {
  description = "ARN of the EFS file system"
  value       = aws_efs_file_system.main.arn
}

output "efs_dns_name" {
  description = "DNS name of the EFS file system"
  value       = aws_efs_file_system.main.dns_name
}

output "mount_target_ids" {
  description = "IDs of EFS mount targets"
  value       = aws_efs_mount_target.main[*].id
}

output "mount_target_dns_names" {
  description = "DNS names of EFS mount targets"
  value       = aws_efs_mount_target.main[*].dns_name
}

output "odoo_access_point_id" {
  description = "EFS access point ID for Odoo (private instance, /odoo)"
  value       = aws_efs_access_point.odoo.id
}

output "odoo_public_access_point_id" {
  description = "EFS access point ID for Odoo public instance (/odoo-public)"
  value       = aws_efs_access_point.odoo_public.id
}

output "moodle_access_point_id" {
  description = "EFS access point ID for Moodle (/moodle, uid=33 www-data)"
  value       = aws_efs_access_point.moodle.id
}

output "osticket_access_point_id" {
  description = "EFS access point ID for osTicket (/osticket, uid=33 www-data)"
  value       = aws_efs_access_point.osticket.id
}
