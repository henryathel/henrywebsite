data "aws_caller_identity" "current" {}

locals {
  # Must match the name created in bootstrap/.
  state_bucket_name = "${var.project}-tfstate-${data.aws_caller_identity.current.account_id}"
}

module "ci" {
  source = "./modules/ci"

  project                  = var.project
  github_owner             = var.github_owner
  infra_repo               = var.infra_repo
  state_bucket_name        = local.state_bucket_name
  github_oidc_provider_arn = var.github_oidc_provider_arn
}
