output "zone_id" {
  description = "Route 53 hosted zone for the domain, for records added by other modules."
  value       = aws_route53_zone.this.zone_id
}

output "name_servers" {
  description = "Set these as custom nameservers at the registrar (Namecheap)."
  value       = aws_route53_zone.this.name_servers
}

output "bucket_name" {
  description = "Private bucket holding the public site content."
  value       = aws_s3_bucket.this["site"].bucket
}

output "bucket_arn" {
  description = "ARN of the site bucket."
  value       = aws_s3_bucket.this["site"].arn
}

output "roles_bucket_name" {
  description = "Private bucket holding the protected role write-ups."
  value       = aws_s3_bucket.this["roles"].bucket
}

output "roles_bucket_arn" {
  description = "ARN of the roles bucket."
  value       = aws_s3_bucket.this["roles"].arn
}

output "distribution_id" {
  description = "CloudFront distribution ID, used for cache invalidations."
  value       = aws_cloudfront_distribution.site.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.site.arn
}

output "site_url" {
  description = "Canonical URL of the site."
  value       = "https://${local.www_domain}/"
}
