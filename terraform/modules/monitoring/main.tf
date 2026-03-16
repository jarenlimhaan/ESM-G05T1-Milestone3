# ==============================================================================
# Monitoring Module - Main Configuration
# ==============================================================================
# This module creates CloudWatch resources for monitoring:
# - Log groups
# - Metric alarms
# - SNS topics for alerts

# ==============================================================================
# Data Sources
# ==============================================================================

data "aws_region" "current" {}

# ==============================================================================
# SNS Topic for Alerts
# ==============================================================================
# SNS topic for sending operational alerts

resource "aws_sns_topic" "alerts" {
  name = "${var.project_name}-${var.environment}-alerts"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-alerts"
    }
  )
}

# Email subscription for alerts
resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email

  # Wait for email confirmation
}

# ==============================================================================
# CloudWatch Log Groups
# ==============================================================================
# Centralized logging for application and system logs

resource "aws_cloudwatch_log_group" "main" {
  name              = "/${var.project_name}/${var.environment}/application-logs"
  retention_in_days = 30

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-logs"
    }
  )
}

resource "aws_cloudwatch_log_stream" "application" {
  name           = "application-stream"
  log_group_name = aws_cloudwatch_log_group.main.name
}

# ==============================================================================
# CloudWatch Metric Alarms for RDS
# ==============================================================================

# RDS CPU High Usage Alarm
resource "aws_cloudwatch_metric_alarm" "rds_cpu_high" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "3"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when RDS CPU utilization exceeds 80% for 15 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.odoo_rds_id
  }

  tags = var.common_tags
}

# RDS Storage Space Low Alarm
resource "aws_cloudwatch_metric_alarm" "rds_storage_low" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = 2147483648 # 2 GB in bytes
  alarm_description   = "Alert when RDS free storage space is less than 2GB"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.odoo_rds_id
  }

  tags = var.common_tags
}

# RDS Database Connections High Alarm
resource "aws_cloudwatch_metric_alarm" "rds_connection_high" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = "300"
  statistic           = "Average"
  threshold           = "80"
  alarm_description   = "Alert when RDS database connections exceed 80 for 10 minutes"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBInstanceIdentifier = var.moodle_rds_id
  }

  tags = var.common_tags
}

# ==============================================================================
# CloudWatch Metric Alarms for EFS
# ==============================================================================

# EFS Burst Credit Balance Low Alarm
resource "aws_cloudwatch_metric_alarm" "efs_burst_credit_low" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-efs-burst-credit-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "BurstCreditBalance"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Average"
  threshold           = 300000000 # 300 GB in bytes
  alarm_description   = "Alert when EFS burst credit balance is low"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    FileSystemId = var.efs_id
  }

  tags = var.common_tags
}

# EFS Data Write I/O High Alarm
resource "aws_cloudwatch_metric_alarm" "efs_connection_high" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-efs-data-io-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "DataWriteIOBytes"
  namespace           = "AWS/EFS"
  period              = "300"
  statistic           = "Sum"
  threshold           = 10737418240 # 10 GB in bytes over 5 minutes
  alarm_description   = "Alert when EFS write I/O is very high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  dimensions = {
    FileSystemId = var.efs_id
  }

  tags = var.common_tags
}
