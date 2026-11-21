# GitHub Actions -> AWS federation.
#
# CI never applies Terraform: applies are run locally by Henry. Pull requests get a
# read-only plan role. Deploy roles for site content are added alongside the resources
# they write to (step 2).

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  github_oidc_host  = "token.actions.githubusercontent.com"
  oidc_provider_arn = coalesce(var.github_oidc_provider_arn, one(aws_iam_openid_connect_provider.github[*].arn))

  account_arn_prefix = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}"
  state_bucket_arn   = "arn:${data.aws_partition.current.partition}:s3:::${var.state_bucket_name}"
}

# AWS validates GitHub's certificate against its own trust store, so no thumbprint is needed.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.github_oidc_provider_arn == null ? 1 : 0

  url            = "https://${local.github_oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
}

# --- Plan role: pull requests on the infra repo only ---------------------------------

data "aws_iam_policy_document" "plan_trust" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    # Fork PRs never receive an OIDC token under the `pull_request` trigger, so this
    # matches only branches pushed to the repo itself.
    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["repo:${var.github_owner}/${var.infra_repo}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.project}-gha-plan"
  description          = "Assumed by GitHub Actions on pull requests to run terraform plan."
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

# Deliberately not the AWS-managed ReadOnlyAccess policy: the account hosts other
# projects, and ReadOnlyAccess would let any PR workflow read their S3 objects and
# configuration. Read access is granted per resource type, scoped to this project's
# name prefix, and grows as later modules add resources.
data "aws_iam_policy_document" "plan" {
  statement {
    sid       = "StateList"
    actions   = ["s3:ListBucket"]
    resources = [local.state_bucket_arn]
  }

  # Read only: CI runs `plan -lock=false`, so it never writes a lock file.
  statement {
    sid       = "StateRead"
    actions   = ["s3:GetObject"]
    resources = ["${local.state_bucket_arn}/infra/*"]
  }

  statement {
    sid = "IamRead"
    actions = [
      "iam:GetOpenIDConnectProvider",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListRolePolicies",
    ]
    resources = [
      "${local.account_arn_prefix}:role/${var.project}-*",
      "${local.account_arn_prefix}:oidc-provider/${local.github_oidc_host}",
    ]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "terraform-plan-read"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}
