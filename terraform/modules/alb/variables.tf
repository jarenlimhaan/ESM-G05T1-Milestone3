# ==============================================================================
# ALB Module Variables
# ==============================================================================
# Variables for configuring Application Load Balancer.

variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# VPC Configuration

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs where the ALB will be deployed"
  type        = list(string)
}

# Security Group

variable "alb_security_group_id" {
  description = "Security group ID for ALB"
  type        = string
}

variable "internal" {
  description = "Whether ALB is internal (true) or internet-facing (false)"
  type        = bool
  default     = true
}

variable "alb_name_suffix" {
  description = "Suffix for ALB and target group names (for example: public, internal)"
  type        = string
  default     = "internal"
}

# Certificate

variable "certificate_arn" {
  description = "ARN of the ACM certificate for HTTPS"
  type        = string
  default     = ""
}

# Common Tags

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_odoo" {
  description = "Whether to create Odoo listener rules and target group attachment"
  type        = bool
  default     = true
}

variable "enable_moodle" {
  description = "Whether to create Moodle listener rules and target group attachment"
  type        = bool
  default     = true
}

variable "enable_osticket" {
  description = "Whether to create osTicket listener rules and target group attachment"
  type        = bool
  default     = true
}

variable "odoo_node_port" {
  description = "Kubernetes NodePort for Odoo"
  type        = number
  default     = 30080
}

variable "odoo_path_patterns" {
  description = "Path patterns to route to Odoo target group"
  type        = list(string)
  default     = ["/odoo*"]
}

variable "odoo_host_headers" {
  description = "Optional host headers to route to Odoo target group"
  type        = list(string)
  default     = []
}

variable "moodle_node_port" {
  description = "Kubernetes NodePort for Moodle"
  type        = number
  default     = 30082
}

variable "moodle_path_patterns" {
  description = "Path patterns to route to Moodle target group"
  type        = list(string)
  default     = ["/moodle*"]
}

variable "moodle_host_headers" {
  description = "Optional host headers to route to Moodle target group"
  type        = list(string)
  default     = []
}

variable "osticket_node_port" {
  description = "Kubernetes NodePort for osTicket"
  type        = number
  default     = 30083
}

variable "osticket_path_patterns" {
  description = "Path patterns to route to osTicket target group"
  type        = list(string)
  default     = ["/osticket*"]
}

variable "osticket_host_headers" {
  description = "Optional host headers to route to osTicket target group"
  type        = list(string)
  default     = []
}

variable "node_group_asg_name" {
  description = "EKS managed node group Auto Scaling Group name"
  type        = string
}
