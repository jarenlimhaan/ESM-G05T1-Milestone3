# ==============================================================================
# ALB Module - Main Configuration
# ==============================================================================
# This module creates an Application Load Balancer for routing traffic
# to Kubernetes services. It supports both internal and public ALBs.

locals {
  # ALB name max length is 32.
  lb_name = substr("${var.project_name}-${var.environment}-${var.alb_name_suffix}-alb", 0, 32)
  # Target group name max length is 32.
  alb_short = var.internal ? "in" : "pu"
  tg_base   = substr("${var.project_name}-${var.environment}-${local.alb_short}", 0, 22)
}

# ==============================================================================
# Load Balancer
# ==============================================================================
# ALB can be internal or internet-facing based on var.internal

resource "aws_lb" "main" {
  name               = local.lb_name
  internal           = var.internal
  load_balancer_type = "application"

  # Deploy in provided subnets
  subnets = var.subnet_ids

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
  name        = "${local.tg_base}-odoo-np"
  port        = var.odoo_node_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 30
    matcher             = "200-399"
    path                = "/"
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

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-odoo-tg"
    }
  )
}

resource "aws_lb_target_group" "moodle" {
  name        = "${local.tg_base}-moodle-np"
  port        = var.moodle_node_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  # Health check configuration
  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 30
    matcher             = "200-399"
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

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-moodle-tg"
    }
  )
}

resource "aws_lb_target_group" "osticket" {
  name        = "${local.tg_base}-ostk-np"
  port        = var.osticket_node_port
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "instance"

  health_check {
    enabled             = true
    healthy_threshold   = 3
    interval            = 30
    matcher             = "200-399"
    path                = "/"
    port                = "traffic-port"
    protocol            = "HTTP"
    timeout             = 5
    unhealthy_threshold = 3
  }

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400
    enabled         = true
  }

  deregistration_delay = 300

  lifecycle {
    create_before_destroy = true
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-osticket-tg"
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
  count        = var.enable_odoo ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.odoo.arn
  }

  condition {
    path_pattern {
      values = var.odoo_path_patterns
    }
  }

  dynamic "condition" {
    for_each = length(var.odoo_host_headers) > 0 ? [1] : []
    content {
      host_header {
        values = var.odoo_host_headers
      }
    }
  }

  tags = var.common_tags
}

resource "aws_lb_listener_rule" "moodle" {
  count        = var.enable_moodle ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.moodle.arn
  }

  condition {
    path_pattern {
      values = var.moodle_path_patterns
    }
  }

  dynamic "condition" {
    for_each = length(var.moodle_host_headers) > 0 ? [1] : []
    content {
      host_header {
        values = var.moodle_host_headers
      }
    }
  }

  tags = var.common_tags
}

resource "aws_lb_listener_rule" "osticket" {
  count        = var.enable_osticket ? 1 : 0
  listener_arn = aws_lb_listener.http.arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.osticket.arn
  }

  condition {
    path_pattern {
      values = var.osticket_path_patterns
    }
  }

  dynamic "condition" {
    for_each = length(var.osticket_host_headers) > 0 ? [1] : []
    content {
      host_header {
        values = var.osticket_host_headers
      }
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
  count        = var.certificate_arn != "" && var.enable_odoo ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.odoo.arn
  }

  condition {
    path_pattern {
      values = var.odoo_path_patterns
    }
  }

  dynamic "condition" {
    for_each = length(var.odoo_host_headers) > 0 ? [1] : []
    content {
      host_header {
        values = var.odoo_host_headers
      }
    }
  }

  tags = var.common_tags
}

resource "aws_lb_listener_rule" "moodle_https" {
  count        = var.certificate_arn != "" && var.enable_moodle ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 200

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.moodle.arn
  }

  condition {
    path_pattern {
      values = var.moodle_path_patterns
    }
  }

  dynamic "condition" {
    for_each = length(var.moodle_host_headers) > 0 ? [1] : []
    content {
      host_header {
        values = var.moodle_host_headers
      }
    }
  }

  tags = var.common_tags
}

resource "aws_lb_listener_rule" "osticket_https" {
  count        = var.certificate_arn != "" && var.enable_osticket ? 1 : 0
  listener_arn = aws_lb_listener.https[0].arn
  priority     = 300

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.osticket.arn
  }

  condition {
    path_pattern {
      values = var.osticket_path_patterns
    }
  }

  dynamic "condition" {
    for_each = length(var.osticket_host_headers) > 0 ? [1] : []
    content {
      host_header {
        values = var.osticket_host_headers
      }
    }
  }

  tags = var.common_tags
}

# Register EKS worker nodes in each enabled target group.
resource "aws_autoscaling_attachment" "odoo" {
  count                  = var.enable_odoo ? 1 : 0
  autoscaling_group_name = var.node_group_asg_name
  lb_target_group_arn    = aws_lb_target_group.odoo.arn
}

resource "aws_autoscaling_attachment" "moodle" {
  count                  = var.enable_moodle ? 1 : 0
  autoscaling_group_name = var.node_group_asg_name
  lb_target_group_arn    = aws_lb_target_group.moodle.arn
}

resource "aws_autoscaling_attachment" "osticket" {
  count                  = var.enable_osticket ? 1 : 0
  autoscaling_group_name = var.node_group_asg_name
  lb_target_group_arn    = aws_lb_target_group.osticket.arn
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
