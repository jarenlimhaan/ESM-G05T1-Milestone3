locals {
  has_public_zone_name  = trimspace(var.public_zone_name) != ""
  has_private_zone_name = trimspace(var.private_zone_name) != ""
}

resource "aws_route53_zone" "public" {
  count = var.create_public_zone && local.has_public_zone_name ? 1 : 0

  name = var.public_zone_name

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-public-zone"
    }
  )
}

resource "aws_route53_zone" "private" {
  count = var.create_private_zone && local.has_private_zone_name ? 1 : 0

  name = var.private_zone_name

  vpc {
    vpc_id = var.vpc_id
  }

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-${var.environment}-private-zone"
    }
  )
}

resource "aws_route53_record" "odoo_public" {
  count = var.create_public_zone && local.has_public_zone_name ? 1 : 0

  zone_id = aws_route53_zone.public[0].zone_id
  name    = "${var.odoo_public_record_name}.${var.public_zone_name}"
  type    = "A"

  alias {
    name                   = var.public_alb_dns_name
    zone_id                = var.public_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "odoo_internal" {
  count = var.create_private_zone && local.has_private_zone_name ? 1 : 0

  zone_id = aws_route53_zone.private[0].zone_id
  name    = "${var.odoo_internal_record_name}.${var.private_zone_name}"
  type    = "A"

  alias {
    name                   = var.internal_alb_dns_name
    zone_id                = var.internal_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "moodle_internal" {
  count = var.create_private_zone && local.has_private_zone_name ? 1 : 0

  zone_id = aws_route53_zone.private[0].zone_id
  name    = "${var.moodle_internal_record_name}.${var.private_zone_name}"
  type    = "A"

  alias {
    name                   = var.internal_alb_dns_name
    zone_id                = var.internal_alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "osticket_internal" {
  count = var.create_private_zone && local.has_private_zone_name ? 1 : 0

  zone_id = aws_route53_zone.private[0].zone_id
  name    = "${var.osticket_internal_record_name}.${var.private_zone_name}"
  type    = "A"

  alias {
    name                   = var.internal_alb_dns_name
    zone_id                = var.internal_alb_zone_id
    evaluate_target_health = true
  }
}
