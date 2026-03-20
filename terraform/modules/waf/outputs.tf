output "web_acl_arn" {
  description = "ARN of the WAF Web ACL attached to the public ALB"
  value       = var.enable_waf ? aws_wafv2_web_acl.public_alb[0].arn : null
}
