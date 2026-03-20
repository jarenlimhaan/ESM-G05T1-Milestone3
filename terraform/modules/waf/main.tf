resource "aws_wafv2_web_acl" "public_alb" {
  count = var.enable_waf ? 1 : 0

  name  = "${var.project_name}-${var.environment}-public-alb-waf"
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-${var.environment}-public-alb-waf"
    sampled_requests_enabled   = true
  }

  # AWS managed baseline protections.
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common-rule-set"
      sampled_requests_enabled   = true
    }
  }

  # Basic per-IP rate limiting.
  rule {
    name     = "RateLimitPerIP"
    priority = 20

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "rate-limit"
      sampled_requests_enabled   = true
    }
  }

  tags = var.common_tags
}

resource "aws_wafv2_web_acl_association" "public_alb" {
  count = var.enable_waf ? 1 : 0

  resource_arn = var.alb_public_arn
  web_acl_arn  = aws_wafv2_web_acl.public_alb[0].arn
}
