output "aws_region" {
  description = "AWS region used by this stack"
  value       = var.aws_region
}

output "cloudtrail_arn" {
  description = "CloudTrail ARN"
  value       = module.cloudtrail.trail_arn
}

output "cloudtrail_s3_bucket" {
  description = "CloudTrail S3 bucket"
  value       = module.cloudtrail.s3_bucket_name
}
