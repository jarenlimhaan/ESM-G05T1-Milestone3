# ==============================================================================
# ALB Module - Main Configuration
# ==============================================================================
# This module creates an internal Application Load Balancer for routing traffic
# to Kubernetes services. The ALB is deployed in private subnets only.

# ==============================================================================
# Load Balancer
# ==============================================================================
# Internal ALB - not accessible from public internet

resource "aws_lb" "main" {
  name               = "${var.project_name}-${var.environment}-alb"
  internal           = true # Internal ALB only
  load_balancer_type = "application"

  # Deploy in private subnets only
  subnets = var.private_subnet_ids

  # Security group for ALB
  security_groups = [var.alb_security_group_id]

  # Enable deletion protection in production
  enable_deletion_protection = false

  # Enable HTTP/2
  enable_http2 = true

  # Idle timeout (default is 60 seconds)
  idle_timeout = 300 # 5 minutes for long-running requests

  # Enable access logs (optional - uncomment for production)
  # access_logs {
  #   bucket  = aws_s3_bucket.alb_logs.bucket
  #   prefix  = "alb-logs"
  #   enabled = true
  # }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-alb"
    }
  )
}

# ==============================================================================
# Target Groups
# ==============================================================================
# Target groups for Odoo and Moodle services

resource "aws_lb_target_group" "odoo" {
  name        = "${var.project_name}-${var.environment}-odoo-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # IP mode for Kubernetes pods

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 30
    matcher             = "200"
    path                = "/web/health"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  # Stickiness for session persistence
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400 # 24 hours
    enabled         = true
  }

  # Deregistration delay
  deregistration_delay = 300 # 5 minutes

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-odoo-tg"
    }
  )
}

resource "aws_lb_target_group" "moodle" {
  name        = "${var.project_name}-${var.environment}-moodle-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip" # IP mode for Kubernetes pods

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 30
    matcher             = "200"
    path                = "/login/index.php" # Moodle health check path
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  # Stickiness for session persistence
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400 # 24 hours
    enabled         = true
  }

  # Deregistration delay
  deregistration_delay = 300 # 5 minutes

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-moodle-tg"
    }
  )
}

# ==============================================================================
# HTTP Listener
# ==============================================================================
# Listens on port 80 and routes based on path patterns

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = 80
  protocol          = "HTTP"

  # Default action - return 404
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404 Not Found"
      status_code  = "404"
    }
  }

  tags = var.common_tags
}

# ==============================================================================
# Listener Rules for HTTP
# ==============================================================================
# Route traffic to Odoo and Moodle based on path

resource "aws_lb_listener_rule" "odoo" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.odoo.arn
  }

  condition {
    path_pattern {
      values = ["/odoo*"]
    }
  }

  tags = var.common_tags
}

resource "aws_lb_listener_rule" "moodle" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.moodle.arn
  }

  condition {
    path_pattern {
      values = ["/moodle*"]
    }
  }

  tags = var.common_tags
}

# ==============================================================================
# HTTPS Listener (Optional - if certificate is provided)
# ==============================================================================
# Listens on port 443 and routes based on path patterns

resource "aws_lb_listener" "https" {
  count = var.certificate_arn != "" ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn   = var.certificate_arn

  # Default action - return 404
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404 Not Found"
      status_code  = "404"
    }
  }

  tags = var.common_tags
}

# HTTPS listener rules (only created if certificate is provided)
resource "aws_lb_listener_rule" "odoo_https" {
  count        = var.certificate_arn != "" ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.odoo.arn
  }

  condition {
    path_pattern {
      values = ["/odoo*"]
    }
  }

  tags = var.common_tags
}

resource "aws_lb_listener_rule" "moodle_https" {
  count        = var.certificate_arn != "" ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.moodle.arn
  }

  condition {
    path_pattern {
      values = ["/moodle*"]
    }
  }

  tags = var.common_tags
}

# ==============================================================================
# S3 Bucket for ALB Access Logs (Optional)
# ==============================================================================
# Uncomment to enable ALB access logging for compliance and debugging

/*
resource "aws_s3_bucket" "alb_logs" {
  bucket = "${var.project_name}-${var.environment}-alb-logs"

  tags = var.common_tags
}

resource "aws_s3_bucket_versioning" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "alb_logs" {
  bucket = aws_s3_bucket.alb_logs.id

  rule {
    id     = "alb-logs-expiration"
    status = "Enabled"

    expiration {
      days = 90  # Retain logs for 90 days
    }

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}
*/
