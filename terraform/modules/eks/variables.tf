# ==============================================================================
# EKS Module Variables
# ==============================================================================
# Variables for configuring EKS cluster and node group.

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# EKS Configuration

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
}

# VPC Configuration

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "IDs of private application subnets"
  type        = list(string)
}

# Security Groups

variable "cluster_security_group_id" {
  description = "Security group ID for EKS cluster"
  type        = string
}

variable "nodes_security_group_id" {
  description = "Security group ID for EKS nodes"
  type        = string
}

# Node Group Configuration

variable "node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
}

variable "node_count_min" {
  description = "Minimum number of EKS nodes"
  type        = number
}

variable "node_count_max" {
  description = "Maximum number of EKS nodes"
  type        = number
}

variable "node_count_desired" {
  description = "Desired number of EKS nodes"
  type        = number
}

# Monitoring

variable "enable_cloudwatch_logging" {
  description = "Enable CloudWatch logging for EKS"
  type        = bool
  default     = true
}

# Common Tags

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
