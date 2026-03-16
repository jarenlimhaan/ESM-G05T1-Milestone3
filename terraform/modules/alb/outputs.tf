# ==============================================================================
# ALB Module Outputs
# ==============================================================================
# Outputs for ALB information.

output "alb_id" {
  description = "ID of the ALB"
  value       = aws_lb.main.id
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = aws_lb.main.arn
}

output "alb_dns_name" {
  description = "DNS name of the ALB"
  value       = aws_lb.main.dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB"
  value       = aws_lb.main.zone_id
}

output "target_group_arn_odoo" {
  description = "ARN of the Odoo target group"
  value       = aws_lb_target_group.odoo.arn
}

output "target_group_arn_moodle" {
  description = "ARN of the Moodle target group"
  value       = aws_lb_target_group.moodle.arn
}

output "listener_arn" {
  description = "ARN of the HTTP listener"
  value       = aws_lb_listener.http.arn
}

output "https_listener_arn" {
  description = "ARN of the HTTPS listener (if certificate provided)"
  value       = var.certificate_arn != "" ? aws_lb_listener.https[0].arn : null
}
