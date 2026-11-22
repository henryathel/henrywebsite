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

  project     = var.project
  domain_name = var.domain_name
}

module "ci" {
  source = "./modules/ci"

  project                  = var.project
  github_owner             = var.github_owner
  github_owner_id          = var.github_owner_id
  infra_repo               = var.infra_repo
  infra_repo_id            = var.infra_repo_id
  state_bucket_name        = local.state_bucket_name
  github_oidc_provider_arn = var.github_oidc_provider_arn
  site_bucket_arn          = module.site.bucket_arn
  distribution_arn         = module.site.distribution_arn
}
