# ==============================================================================
# Backup Module Outputs
# ==============================================================================
# Outputs for backup configuration.

output "backup_vault_id" {
  description = "ID of the AWS Backup vault"
  value       = aws_backup_vault.main.id
}

output "backup_vault_arn" {
  description = "ARN of the AWS Backup vault"
  value       = aws_backup_vault.main.arn
}

output "backup_plan_id" {
  description = "ID of the backup plan"
  value       = aws_backup_plan.main.id
}

output "backup_plan_arn" {
  description = "ARN of the backup plan"
  value       = aws_backup_plan.main.arn
}

output "backup_selection_id" {
  description = "ID of the backup selection"
  value       = aws_backup_selection.main.id
}
