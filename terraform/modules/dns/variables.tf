variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID used for private hosted zone association"
  type        = string
}

variable "create_public_zone" {
  description = "Whether to create a public hosted zone"
  type        = bool
  default     = false
}

variable "public_zone_name" {
  description = "Public hosted zone name"
  type        = string
  default     = ""
}

variable "create_private_zone" {
  description = "Whether to create a private hosted zone"
  type        = bool
  default     = true
}

variable "private_zone_name" {
  description = "Private hosted zone name"
  type        = string
  default     = "internal.esm.local"
}

variable "odoo_public_record_name" {
  description = "Record prefix for public Odoo endpoint"
  type        = string
  default     = "odoo"
}

variable "odoo_internal_record_name" {
  description = "Record prefix for internal Odoo endpoint"
  type        = string
  default     = "odoo"
}

variable "moodle_internal_record_name" {
  description = "Record prefix for internal Moodle endpoint"
  type        = string
  default     = "moodle"
}

variable "osticket_internal_record_name" {
  description = "Record prefix for internal osTicket endpoint"
  type        = string
  default     = "osticket"
}

variable "public_alb_dns_name" {
  description = "DNS name of public ALB"
  type        = string
}

variable "public_alb_zone_id" {
  description = "Route53 hosted zone ID of public ALB"
  type        = string
}

variable "internal_alb_dns_name" {
  description = "DNS name of internal ALB"
  type        = string
}

variable "internal_alb_zone_id" {
  description = "Route53 hosted zone ID of internal ALB"
  type        = string
}

variable "common_tags" {
  description = "Common tags to apply to resources"
  type        = map(string)
  default     = {}
}
