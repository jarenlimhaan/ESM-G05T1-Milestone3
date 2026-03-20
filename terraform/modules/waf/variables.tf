variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "alb_public_arn" {
  description = "ARN of the public ALB"
  type        = string
}

variable "enable_waf" {
  description = "Enable WAF resources"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Per-IP rate limit over 5 minutes"
  type        = number
  default     = 2000
}

variable "common_tags" {
  description = "Common tags to apply to all resources"
  type        = map(string)
  default     = {}
}
