output "oidc_provider_arn" {
  description = "ARN of the GitHub Actions OIDC provider, for roles added in later modules."
  value       = local.oidc_provider_arn
}

output "plan_role_arn" {
  description = "Role assumed by pull-request workflows to run `terraform plan`."
  value       = aws_iam_role.plan.arn
}
