output "plan_role_arn" {
  description = "Set as the AWS_PLAN_ROLE_ARN repository variable in GitHub."
  value       = module.ci.plan_role_arn
}

output "site_deploy_role_arn" {
  description = "Set as the AWS_SITE_DEPLOY_ROLE_ARN repository variable in GitHub."
  value       = module.ci.site_deploy_role_arn
}

output "content_deploy_role_arn" {
  description = "Set as the AWS_CONTENT_DEPLOY_ROLE_ARN variable in the henrywebsite-content repo."
  value       = module.ci.content_deploy_role_arn
}

output "roles_bucket" {
  description = "Set as the ROLES_BUCKET variable in the henrywebsite-content repo."
  value       = module.site.roles_bucket_name
}

output "site_bucket" {
  description = "Set as the SITE_BUCKET repository variable in GitHub."
  value       = module.site.bucket_name
}

output "cloudfront_distribution_id" {
  description = "Set as the CLOUDFRONT_DISTRIBUTION_ID repository variable in GitHub."
  value       = module.site.distribution_id
}

output "name_servers" {
  description = "Enter these as Custom DNS nameservers for the domain at Namecheap."
  value       = module.site.name_servers
}

output "site_url" {
  description = "Canonical URL of the site."
  value       = module.site.site_url
}
