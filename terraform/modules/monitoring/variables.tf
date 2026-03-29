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

variable "enable_moodle_pod_cpu_alarm" {
  description = "Enable Moodle pod CPU utilization alarm using ContainerInsights metrics"
  type        = bool
  default     = true
}

variable "enable_container_insights_metric_alarms" {
  description = "Enable ContainerInsights SEARCH-based metric alarms (may be unsupported in some AWS accounts/regions)"
  type        = bool
  default     = false
}

variable "eks_cluster_name" {
  description = "EKS cluster name used for ContainerInsights dimensions"
  type        = string
}

variable "moodle_namespace" {
  description = "Kubernetes namespace where Moodle runs"
  type        = string
  default     = "moodle-private"
}

variable "moodle_pod_cpu_threshold" {
  description = "Average Moodle pod CPU utilization threshold (percent)"
  type        = number
  default     = 80
}

variable "enable_odoo_pod_cpu_alarm" {
  description = "Enable Odoo pod CPU utilization alarms using ContainerInsights metrics"
  type        = bool
  default     = true
}

variable "odoo_namespaces" {
  description = "Kubernetes namespaces where Odoo runs"
  type        = list(string)
  default     = ["odoo-public", "odoo-private"]
}

variable "odoo_pod_cpu_threshold" {
  description = "Average Odoo pod CPU utilization threshold (percent)"
  type        = number
  default     = 70
}

variable "moodle_pod_memory_threshold" {
  description = "Average Moodle pod memory utilization threshold (percent)"
  type        = number
  default     = 80
}

variable "pod_restart_threshold" {
  description = "Threshold for pod restarts in the evaluation window"
  type        = number
  default     = 3
}

variable "monitored_namespaces" {
  description = "Kubernetes namespaces to monitor for pod restart alarms"
  type        = list(string)
  default     = ["odoo-public", "odoo-private", "moodle-private", "osticket-private"]
}

variable "public_alb_arn_suffix" {
  description = "Public ALB ARN suffix for ApplicationELB metrics"
  type        = string
}

variable "internal_alb_arn_suffix" {
  description = "Internal ALB ARN suffix for ApplicationELB metrics"
  type        = string
}

variable "public_odoo_target_group_arn_suffix" {
  description = "Public Odoo target group ARN suffix for ALB target health metrics"
  type        = string
}

variable "internal_moodle_target_group_arn_suffix" {
  description = "Internal Moodle target group ARN suffix for ALB target health metrics"
  type        = string
}

variable "alb_5xx_rate_threshold_percent" {
  description = "ALB HTTP 5xx error rate threshold percentage"
  type        = number
  default     = 1
}

variable "eks_node_cpu_threshold" {
  description = "EKS node CPU utilization threshold (percent)"
  type        = number
  default     = 85
}

variable "eks_node_memory_threshold" {
  description = "EKS node memory utilization threshold (percent)"
  type        = number
  default     = 85
}

variable "monthly_budget_limit_usd" {
  description = "Monthly AWS cost budget limit in USD"
  type        = number
  default     = 50
}

# Common Tags

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
