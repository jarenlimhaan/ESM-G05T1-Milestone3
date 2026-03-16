# ==============================================================================
# Monitoring Module Outputs
# ==============================================================================
# Outputs for monitoring configuration.

output "sns_topic_arn" {
  description = "ARN of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.id
}

output "sns_topic_name" {
  description = "Name of the SNS topic for alerts"
  value       = aws_sns_topic.alerts.name
}

output "log_group_arn" {
  description = "ARN of the main CloudWatch log group"
  value       = aws_cloudwatch_log_group.main.arn
}

output "dashboard_url" {
  description = "URL of the CloudWatch dashboard"
  value       = "https://${data.aws_region.current.name}.console.aws.amazon.com/cloudwatch/home?region=${data.aws_region.current.name}#dashboards:name=${var.project_name}-${var.environment}-dashboard"
}

output "alarm_arns" {
  description = "List of alarm ARNs created"
  value = concat(
    aws_cloudwatch_metric_alarm.rds_cpu_high[*].arn,
    aws_cloudwatch_metric_alarm.rds_storage_low[*].arn,
    aws_cloudwatch_metric_alarm.rds_connection_high[*].arn,
    aws_cloudwatch_metric_alarm.efs_burst_credit_low[*].arn,
    aws_cloudwatch_metric_alarm.efs_connection_high[*].arn
  )
}
