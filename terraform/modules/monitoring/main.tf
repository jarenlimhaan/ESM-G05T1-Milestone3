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
data "aws_caller_identity" "current" {}

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
  threshold           = 322122547200 # 300 GiB in bytes (300 × 1,073,741,824)
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

# ==============================================================================
# CloudWatch Metric Alarm for Moodle Pods (ContainerInsights)
# ==============================================================================
# This alarm triggers when average Moodle pod CPU utilization in the Moodle
# namespace exceeds threshold. It requires ContainerInsights pod metrics.

resource "aws_cloudwatch_metric_alarm" "moodle_pod_cpu_high" {
  count = var.enable_monitoring && var.enable_moodle_pod_cpu_alarm && var.enable_container_insights_metric_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-moodle-pod-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  threshold           = var.moodle_pod_cpu_threshold
  alarm_description   = "Alert when average Moodle pod CPU utilization is high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "moodle_cpu_ts"
    return_data = false
    period      = 60
    expression  = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_cpu_utilization\" ClusterName=\"${var.eks_cluster_name}\" Namespace=\"${var.moodle_namespace}\"', 'Average', 60)"
  }

  metric_query {
    id          = "moodle_cpu_avg"
    label       = "Average Moodle pod CPU utilization"
    return_data = true
    period      = 60
    expression  = "AVG(moodle_cpu_ts)"
  }

  tags = var.common_tags
}

# Odoo pod CPU alarms per namespace (public/private by default)
resource "aws_cloudwatch_metric_alarm" "odoo_pod_cpu_high" {
  for_each = var.enable_monitoring && var.enable_odoo_pod_cpu_alarm && var.enable_container_insights_metric_alarms ? toset(var.odoo_namespaces) : toset([])

  alarm_name          = "${var.project_name}-${var.environment}-${each.value}-pod-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  threshold           = var.odoo_pod_cpu_threshold
  alarm_description   = "Alert when average Odoo pod CPU utilization is high in namespace ${each.value}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "odoo_cpu_ts"
    return_data = false
    period      = 60
    expression  = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_cpu_utilization\" ClusterName=\"${var.eks_cluster_name}\" Namespace=\"${each.value}\"', 'Average', 60)"
  }

  metric_query {
    id          = "odoo_cpu_avg"
    label       = "Average Odoo pod CPU utilization (${each.value})"
    return_data = true
    period      = 60
    expression  = "AVG(odoo_cpu_ts)"
  }

  tags = var.common_tags
}

# Moodle pod memory utilization alarm (matches HPA memory threshold)
resource "aws_cloudwatch_metric_alarm" "moodle_pod_memory_high" {
  count = var.enable_monitoring && var.enable_container_insights_metric_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-moodle-pod-memory-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 5
  threshold           = var.moodle_pod_memory_threshold
  alarm_description   = "Alert when average Moodle pod memory utilization is high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "moodle_mem_ts"
    return_data = false
    period      = 60
    expression  = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_memory_utilization\" ClusterName=\"${var.eks_cluster_name}\" Namespace=\"${var.moodle_namespace}\"', 'Average', 60)"
  }

  metric_query {
    id          = "moodle_mem_avg"
    label       = "Average Moodle pod memory utilization"
    return_data = true
    period      = 60
    expression  = "AVG(moodle_mem_ts)"
  }

  tags = var.common_tags
}

# Pod restart alarm per namespace (detect crash loops / instability)
resource "aws_cloudwatch_metric_alarm" "pod_restarts_high" {
  for_each = var.enable_monitoring && var.enable_container_insights_metric_alarms ? toset(var.monitored_namespaces) : toset([])

  alarm_name          = "${var.project_name}-${var.environment}-${each.value}-pod-restarts-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 10
  threshold           = var.pod_restart_threshold
  alarm_description   = "Alert when pod restarts are high in namespace ${each.value}"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "restarts_ts"
    return_data = false
    period      = 60
    expression  = "SEARCH('{ContainerInsights,ClusterName,Namespace,PodName} MetricName=\"pod_number_of_container_restarts\" ClusterName=\"${var.eks_cluster_name}\" Namespace=\"${each.value}\"', 'Average', 60)"
  }

  metric_query {
    id          = "restarts_sum"
    label       = "Pod restarts sum (${each.value})"
    return_data = true
    period      = 60
    expression  = "SUM(restarts_ts)"
  }

  tags = var.common_tags
}

# ALB target 5xx rate alarm (public ALB)
resource "aws_cloudwatch_metric_alarm" "public_alb_5xx_rate_high" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-public-alb-5xx-rate-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = var.alb_5xx_rate_threshold_percent
  alarm_description   = "Alert when public ALB target 5xx error rate exceeds threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id = "err"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.public_alb_arn_suffix
      }
    }
    return_data = false
  }

  metric_query {
    id = "req"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.public_alb_arn_suffix
      }
    }
    return_data = false
  }

  metric_query {
    id          = "rate"
    period      = 300
    expression  = "IF(req>0, (err/req)*100, 0)"
    label       = "Public ALB target 5xx rate (%)"
    return_data = true
  }

  tags = var.common_tags
}

# ALB target 5xx rate alarm (internal ALB)
resource "aws_cloudwatch_metric_alarm" "internal_alb_5xx_rate_high" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-internal-alb-5xx-rate-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = var.alb_5xx_rate_threshold_percent
  alarm_description   = "Alert when internal ALB target 5xx error rate exceeds threshold"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id = "err"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.internal_alb_arn_suffix
      }
    }
    return_data = false
  }

  metric_query {
    id = "req"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 300
      stat        = "Sum"
      dimensions = {
        LoadBalancer = var.internal_alb_arn_suffix
      }
    }
    return_data = false
  }

  metric_query {
    id          = "rate"
    period      = 300
    expression  = "IF(req>0, (err/req)*100, 0)"
    label       = "Internal ALB target 5xx rate (%)"
    return_data = true
  }

  tags = var.common_tags
}

# Odoo availability proxy: unhealthy hosts in public ALB target group
resource "aws_cloudwatch_metric_alarm" "odoo_public_unhealthy_hosts" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-odoo-public-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Alert when public Odoo target group has unhealthy hosts"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.public_alb_arn_suffix
    TargetGroup  = var.public_odoo_target_group_arn_suffix
  }

  tags = var.common_tags
}

# Moodle availability proxy: unhealthy hosts in internal ALB target group
resource "aws_cloudwatch_metric_alarm" "moodle_internal_unhealthy_hosts" {
  count = var.enable_monitoring ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-moodle-internal-unhealthy-hosts"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "UnHealthyHostCount"
  namespace           = "AWS/ApplicationELB"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "Alert when internal Moodle target group has unhealthy hosts"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  dimensions = {
    LoadBalancer = var.internal_alb_arn_suffix
    TargetGroup  = var.internal_moodle_target_group_arn_suffix
  }

  tags = var.common_tags
}

# EKS node CPU utilization alarm
resource "aws_cloudwatch_metric_alarm" "eks_node_cpu_high" {
  count = var.enable_monitoring && var.enable_container_insights_metric_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-eks-node-cpu-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 5
  threshold           = var.eks_node_cpu_threshold
  alarm_description   = "Alert when average EKS node CPU utilization is high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "node_cpu_ts"
    return_data = false
    period      = 60
    expression  = "SEARCH('{ContainerInsights,ClusterName,NodeName} MetricName=\"node_cpu_utilization\" ClusterName=\"${var.eks_cluster_name}\"', 'Average', 60)"
  }

  metric_query {
    id          = "node_cpu_avg"
    label       = "Average EKS node CPU utilization"
    return_data = true
    period      = 60
    expression  = "AVG(node_cpu_ts)"
  }

  tags = var.common_tags
}

# EKS node memory utilization alarm
resource "aws_cloudwatch_metric_alarm" "eks_node_memory_high" {
  count = var.enable_monitoring && var.enable_container_insights_metric_alarms ? 1 : 0

  alarm_name          = "${var.project_name}-${var.environment}-eks-node-memory-high"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 5
  threshold           = var.eks_node_memory_threshold
  alarm_description   = "Alert when average EKS node memory utilization is high"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "node_mem_ts"
    return_data = false
    period      = 60
    expression  = "SEARCH('{ContainerInsights,ClusterName,NodeName} MetricName=\"node_memory_utilization\" ClusterName=\"${var.eks_cluster_name}\"', 'Average', 60)"
  }

  metric_query {
    id          = "node_mem_avg"
    label       = "Average EKS node memory utilization"
    return_data = true
    period      = 60
    expression  = "AVG(node_mem_ts)"
  }

  tags = var.common_tags
}

# Budget alert: notify at 80% of monthly budget
resource "aws_budgets_budget" "monthly_cost" {
  name              = "${var.project_name}-${var.environment}-monthly-budget"
  budget_type       = "COST"
  limit_amount      = tostring(var.monthly_budget_limit_usd)
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2024-01-01_00:00"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.alert_email]
    subscriber_sns_topic_arns  = [aws_sns_topic.alerts.arn]
  }

  cost_filter {
    name   = "LinkedAccount"
    values = [data.aws_caller_identity.current.account_id]
  }
}
