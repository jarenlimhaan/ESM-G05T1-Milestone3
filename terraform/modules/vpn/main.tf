# ==============================================================================
# VPN Module - Main Configuration
# ==============================================================================
# This module creates AWS Client VPN endpoint for secure internal access.
# Users connect using the AWS VPN Client application.

# ==============================================================================
# Local Values
# ==============================================================================

locals {
  use_imported_cert = var.server_certificate_arn != ""
}

# ==============================================================================
# ACM Certificates (for VPN Server and Client)
# ==============================================================================
# Create self-signed certificates if no imported certificate is provided
# For production, use your own CA-issued certificates

# Generate private key for VPN server
resource "tls_private_key" "vpn_server" {
  count     = local.use_imported_cert ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate self-signed certificate for VPN server
resource "tls_self_signed_cert" "vpn_server" {
  count           = local.use_imported_cert ? 0 : 1
  private_key_pem = tls_private_key.vpn_server[0].private_key_pem

  validity_period_hours = 87600 # 10 years
  is_ca_certificate     = true

  subject {
    common_name  = "vpn.esm.local"
    organization = "ESM Enterprise"
  }
  allowed_uses = [
    "cert_signing",
    "crl_signing",
    "key_encipherment",
    "digital_signature",
    "server_auth"
  ]
}

# Import server certificate to ACM
resource "aws_acm_certificate" "server" {
  count            = local.use_imported_cert ? 0 : 1
  private_key      = tls_private_key.vpn_server[0].private_key_pem
  certificate_body = tls_self_signed_cert.vpn_server[0].cert_pem

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-vpn-server-cert"
    }
  )

  depends_on = [time_sleep.wait_for_cert_validity]
}

# Generate private key for VPN client
resource "tls_private_key" "vpn_client" {
  count     = local.use_imported_cert ? 0 : 1
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Generate client certificate signed by server certificate
resource "tls_locally_signed_cert" "vpn_client" {
  count              = local.use_imported_cert ? 0 : 1
  cert_request_pem   = tls_cert_request.vpn_client[0].cert_request_pem
  ca_private_key_pem = tls_private_key.vpn_server[0].private_key_pem
  ca_cert_pem        = tls_self_signed_cert.vpn_server[0].cert_pem

  validity_period_hours = 87600 # 10 years
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth"
  ]
}

# Give generated cert timestamps time to be safely in ACM validity window.
resource "time_sleep" "wait_for_cert_validity" {
  count           = local.use_imported_cert ? 0 : 1
  create_duration = "90s"

  depends_on = [
    tls_self_signed_cert.vpn_server,
    tls_locally_signed_cert.vpn_client
  ]
}

resource "tls_cert_request" "vpn_client" {
  count           = local.use_imported_cert ? 0 : 1
  private_key_pem = tls_private_key.vpn_client[0].private_key_pem
  subject {
    common_name  = "vpn-client.esm.local"
    organization = "ESM Enterprise"
  }
}

# Import client certificate to ACM
resource "aws_acm_certificate" "client" {
  count            = local.use_imported_cert ? 0 : 1
  private_key      = tls_private_key.vpn_client[0].private_key_pem
  certificate_body = tls_locally_signed_cert.vpn_client[0].cert_pem

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-vpn-client-cert"
    }
  )

  depends_on = [time_sleep.wait_for_cert_validity]
}

# ==============================================================================
# VPN Endpoint
# ==============================================================================
# AWS Client VPN endpoint for secure remote access

resource "aws_ec2_client_vpn_endpoint" "main" {
  description            = "ESM Enterprise Client VPN Endpoint"
  client_cidr_block      = var.vpn_client_cidr
  server_certificate_arn = local.use_imported_cert ? var.server_certificate_arn : aws_acm_certificate.server[0].arn

  # Authentication - use certificate-based authentication
  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = local.use_imported_cert ? var.server_certificate_arn : aws_acm_certificate.server[0].arn
  }

  # Connection logging (optional - use CloudWatch Logs for audit)
  connection_log_options {
    enabled = false # Disable for this demo
    # enabled = true
    # cloudwatch_log_group = aws_cloudwatch_log_group.vpn.name
    # cloudwatch_log_stream = "vpn-connection-stream"
  }

  # DNS configuration
  dns_servers = ["10.0.0.2"] # Use VPC DNS resolver

  # VPN protocol
  transport_protocol = "tcp"

  # VPN port
  vpn_port = 443

  # Enable split tunnel - only traffic to VPC goes through VPN
  split_tunnel = true

  # VPC association
  vpc_id              = var.vpc_id
  self_service_portal = "enabled"

  # Security group for VPN
  security_group_ids = [var.vpn_security_group_id]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-vpn"
    }
  )

  # Wait for certificate to be validated
  depends_on = [
    aws_acm_certificate.server,
    aws_acm_certificate.client
  ]
}

# ==============================================================================
# VPN Network Association
# ==============================================================================
# Associate VPN endpoint with private subnets for access to internal resources

resource "aws_ec2_client_vpn_network_association" "main" {
  count = length(var.private_subnet_ids)

  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  subnet_id              = var.private_subnet_ids[count.index]

  # Associate each subnet for high availability
}

# ==============================================================================
# VPN Authorization Rules
# ==============================================================================
# Define which VPN clients can access which networks

resource "aws_ec2_client_vpn_authorization_rule" "main" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  target_network_cidr    = "0.0.0.0/0" # Allow access to entire VPC (refine in production)
  authorize_all_groups   = true

  # For production, use specific groups:
  # access_group_id = aws_directory_service_directory.users.id
}

# ==============================================================================
# VPN Route Configuration
# ==============================================================================
# Add routes for VPN traffic

resource "aws_ec2_client_vpn_route" "internet" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.main.id
  destination_cidr_block = "0.0.0.0/0"
  target_vpc_subnet_id   = var.private_subnet_ids[0]

  # Client VPN routes are eventually consistent in AWS.
  # Ensure route creation waits for subnet association + authorization
  # and allow a longer create window to avoid transient timeout failures.
  depends_on = [
    aws_ec2_client_vpn_network_association.main,
    aws_ec2_client_vpn_authorization_rule.main
  ]

  timeouts {
    create = "15m"
    delete = "15m"
  }
}

# ==============================================================================
# SNS Topic for VPN Alerts (Optional)
# ==============================================================================
# Send alerts when VPN endpoint status changes

resource "aws_sns_topic" "vpn_alerts" {
  name = "${var.project_name}-${var.environment}-vpn-alerts"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-vpn-alerts"
    }
  )
}

resource "aws_cloudwatch_metric_alarm" "vpn_status" {
  alarm_name          = "${var.project_name}-${var.environment}-vpn-status"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = "2"
  metric_name         = "ClientVpnEndpointStatus"
  namespace           = "AWS/ClientVPN"
  period              = "300"
  statistic           = "Minimum"
  threshold           = "1"
  alarm_description   = "VPN endpoint status alarm"
  alarm_actions       = [aws_sns_topic.vpn_alerts.arn]
  ok_actions          = [aws_sns_topic.vpn_alerts.arn]

  dimensions = {
    ClientVpnEndpointId = aws_ec2_client_vpn_endpoint.main.id
  }

  tags = var.common_tags
}

# ==============================================================================
# CloudWatch Log Group for VPN Connection Logs (Optional)
# ==============================================================================
# Enable for audit and compliance

/*
resource "aws_cloudwatch_log_group" "vpn" {
  name              = "/aws/vpn/${var.project_name}-${var.environment}"
  retention_in_days = 30

  tags = var.common_tags
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "vpn-connection-stream"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}
*/
