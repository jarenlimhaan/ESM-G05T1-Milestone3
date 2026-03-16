# ==============================================================================
# VPN Module Outputs
# ==============================================================================
# Outputs for VPN configuration.

output "vpn_endpoint_id" {
  description = "ID of the VPN Client endpoint"
  value       = aws_ec2_client_vpn_endpoint.main.id
}

output "vpn_endpoint_arn" {
  description = "ARN of the VPN Client endpoint"
  value       = aws_ec2_client_vpn_endpoint.main.arn
}

output "vpn_endpoint_dns" {
  description = "DNS name of the VPN Client endpoint"
  value       = aws_ec2_client_vpn_endpoint.main.dns_name
}

output "vpn_server_certificate_arn" {
  description = "ARN of the VPN server certificate"
  value       = var.server_certificate_arn != "" ? var.server_certificate_arn : aws_acm_certificate.server[0].arn
}

output "vpn_client_certificate_arn" {
  description = "ARN of the VPN client certificate"
  value       = var.server_certificate_arn != "" ? null : aws_acm_certificate.client[0].arn
}
