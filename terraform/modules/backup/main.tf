# ==============================================================================
# Backup Module - Main Configuration
# ==============================================================================
# This module creates AWS Backup vault and plan for automated backups.

# ==============================================================================
# IAM Role for Backup
# ==============================================================================

resource "aws_iam_role" "backup" {
  name = "${var.project_name}-${var.environment}-backup-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
      }
    ]
  })

  tags = var.common_tags
}

resource "aws_iam_role_policy_attachment" "backup" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
  role       = aws_iam_role.backup.name
}

# ==============================================================================
# Backup Vault
# ==============================================================================

resource "aws_backup_vault" "main" {
  name = "${var.project_name}-${var.environment}-backup-vault"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-backup-vault"
    }
  )
}

# ==============================================================================
# Backup Plan
# ==============================================================================

resource "aws_backup_plan" "main" {
  name = "${var.project_name}-${var.environment}-backup-plan"

  rule {
    rule_name         = "daily-backup-rule"
    target_vault_name = aws_backup_vault.main.name

    # Schedule: Daily at 3 AM UTC
    schedule = var.backup_schedule

    # Backup window
    start_window      = 60
    completion_window = 180

    # Lifecycle: Keep backups for specified days
    lifecycle {
      delete_after = var.backup_retention_days
    }
  }

  tags = var.common_tags
}

# ==============================================================================
# Backup Selection
# ==============================================================================

resource "aws_backup_selection" "main" {
  name         = "${var.project_name}-${var.environment}-backup-selection"
  plan_id      = aws_backup_plan.main.id
  iam_role_arn = aws_iam_role.backup.arn

  resources = [
    # Backup RDS instances
    var.odoo_rds_arn,
    var.moodle_rds_arn,
    # Backup EFS file system
    var.efs_arn,
  ]
}

# ==============================================================================
# Notification Settings
# ==============================================================================

resource "aws_sns_topic" "backup_notifications" {
  name = "${var.project_name}-${var.environment}-backup-notifications"

  tags = var.common_tags
}

resource "aws_backup_vault_notifications" "main" {
  backup_vault_name = aws_backup_vault.main.name
  sns_topic_arn     = aws_sns_topic.backup_notifications.arn
  backup_vault_events = [
    "BACKUP_JOB_STARTED",
    "BACKUP_JOB_COMPLETED",
    "BACKUP_JOB_FAILED",
    "RESTORE_JOB_STARTED",
    "RESTORE_JOB_COMPLETED",
    "RESTORE_JOB_FAILED",
    "RECOVERY_POINT_MODIFIED",
    "BACKUP_PLAN_CREATED",
    "BACKUP_PLAN_MODIFIED"
  ]

  depends_on = [aws_sns_topic_policy.backup_notifications]
}

resource "aws_sns_topic_policy" "backup_notifications" {
  arn = aws_sns_topic.backup_notifications.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action   = "SNS:Publish"
        Resource = aws_sns_topic.backup_notifications.arn
      }
    ]
  })
}

# ==============================================================================
# CloudWatch Alarms for Backup Jobs
# ==============================================================================

# NumberOfBackupJobsFailed is the correct account-wide AWS/Backup metric.
# BackupJobStatus does not exist and would never fire.
resource "aws_cloudwatch_metric_alarm" "backup_job_failed" {
  alarm_name          = "${var.project_name}-${var.environment}-backup-job-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "NumberOfBackupJobsFailed"
  namespace           = "AWS/Backup"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "Alert when any AWS Backup job fails"
  alarm_actions       = [aws_sns_topic.backup_notifications.arn]

  tags = var.common_tags
}
