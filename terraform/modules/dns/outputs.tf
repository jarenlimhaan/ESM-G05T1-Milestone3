output "public_zone_id" {
  description = "Public hosted zone ID"
  value       = length(aws_route53_zone.public) > 0 ? aws_route53_zone.public[0].zone_id : null
}

output "private_zone_id" {
  description = "Private hosted zone ID"
  value       = length(aws_route53_zone.private) > 0 ? aws_route53_zone.private[0].zone_id : null
}

output "odoo_public_fqdn" {
  description = "Public Odoo DNS record"
  value       = length(aws_route53_record.odoo_public) > 0 ? aws_route53_record.odoo_public[0].fqdn : null
}

output "odoo_internal_fqdn" {
  description = "Internal Odoo DNS record"
  value       = length(aws_route53_record.odoo_internal) > 0 ? aws_route53_record.odoo_internal[0].fqdn : null
}

output "moodle_internal_fqdn" {
  description = "Internal Moodle DNS record"
  value       = length(aws_route53_record.moodle_internal) > 0 ? aws_route53_record.moodle_internal[0].fqdn : null
}

output "osticket_internal_fqdn" {
  description = "Internal osTicket DNS record"
  value       = length(aws_route53_record.osticket_internal) > 0 ? aws_route53_record.osticket_internal[0].fqdn : null
}
