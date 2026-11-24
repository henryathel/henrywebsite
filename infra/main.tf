data "aws_caller_identity" "current" {}

locals {
  # Must match the name created in bootstrap/.
  state_bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

module "site" {
  source = "./modules/site"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project            = var.project
  domain_name        = var.domain_name
  api_domain         = module.auth.api_domain
  api_origin_secret  = module.auth.origin_secret
  roles_key_group_id = module.auth.key_group_id
  face_function_arn  = module.faces.function_arn
}

module "faces" {
  source = "./modules/faces"

  project     = var.project
  bucket_name = module.site.bucket_name
}

module "auth" {
  source = "./modules/auth"

  project                = var.project
  domain_name            = var.domain_name
  zone_id                = module.site.zone_id
  lambda_package         = "${path.root}/../lambdas/dist/auth.zip"
  signing_public_key_pem = file("${path.root}/keys/cookie-signing-public.pem")
  signing_key_parameter  = var.signing_key_parameter
  code_ttl_minutes       = var.code_ttl_minutes
  cookie_ttl_days        = var.cookie_ttl_days
  ses_test_recipients    = var.ses_test_recipients
}

module "alerts" {
  source = "./modules/alerts"

  project             = var.project
  domain_name         = var.domain_name
  notification_email  = var.notification_email
  monthly_budget_usd  = var.monthly_budget_usd
  visitors_stream_arn = module.auth.visitors_stream_arn
}

module "ci" {
  source = "./modules/ci"

  project                  = var.project
  github_owner             = var.github_owner
  github_owner_id          = var.github_owner_id
  infra_repo               = var.infra_repo
  infra_repo_id            = var.infra_repo_id
  content_repo             = var.content_repo
  content_repo_id          = var.content_repo_id
  state_bucket_name        = local.state_bucket_name
  github_oidc_provider_arn = var.github_oidc_provider_arn
  site_bucket_arn          = module.site.bucket_arn
  roles_bucket_arn         = module.site.roles_bucket_arn
  distribution_arn         = module.site.distribution_arn
}
