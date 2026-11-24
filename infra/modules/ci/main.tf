# GitHub Actions -> AWS federation.
#
# CI never applies Terraform: applies are run locally by Henry. Pull requests get a
# read-only plan role; pushes to main get roles that can only publish content: public
# pages from this repo, and role write-ups from the private content repo.

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  github_oidc_host  = "token.actions.githubusercontent.com"
  oidc_provider_arn = coalesce(var.github_oidc_provider_arn, one(aws_iam_openid_connect_provider.github[*].arn))

  # GitHub's immutable subject format pins the numeric owner and repo IDs, so a deleted
  # and re-created repo of the same name can't assume these roles.
  infra_repo_subject   = "repo:${var.github_owner}@${var.github_owner_id}/${var.infra_repo}@${var.infra_repo_id}"
  content_repo_subject = "repo:${var.github_owner}@${var.github_owner_id}/${var.content_repo}@${var.content_repo_id}"

  partition  = data.aws_partition.current.partition
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  account_arn_prefix = "arn:${local.partition}:iam::${local.account_id}"
  state_bucket_arn   = "arn:${local.partition}:s3:::${var.state_bucket_name}"
  regional_prefix    = "${local.region}:${local.account_id}"
}

data "aws_region" "current" {}

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
      values   = ["${local.infra_repo_subject}:pull_request"]
    }
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.project}-gha-plan"
  description          = "Assumed by GitHub Actions on pull requests to run terraform plan."
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  max_session_duration = 3600
}

# Deliberately not the AWS-managed ReadOnlyAccess policy: that includes s3:GetObject and
# ssm:GetParameter, so any PR workflow could read the protected /roles/* pages and the
# cookie-signing key. Instead, read access covers configuration only, per resource type,
# and grows as later modules add resources.
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

  # Bucket configuration only. ListBucket is needed for HeadBucket; there is no GetObject.
  statement {
    sid = "BucketConfigRead"
    actions = [
      "s3:GetAccelerateConfiguration",
      "s3:GetBucket*",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:ListBucket",
    ]
    resources = [var.site_bucket_arn, var.roles_bucket_arn]
  }

  statement {
    sid = "CertificateRead"
    actions = [
      "acm:DescribeCertificate",
      "acm:GetCertificate",
      "acm:ListTagsForCertificate",
    ]
    resources = ["arn:${local.partition}:acm:us-east-1:${local.account_id}:certificate/*"]
  }

  statement {
    sid = "CloudFrontRead"
    actions = [
      "cloudfront:Describe*",
      "cloudfront:Get*",
      "cloudfront:ListTagsForResource",
    ]
    resources = ["arn:${local.partition}:cloudfront::${local.account_id}:*"]
  }

  # These CloudFront actions have no resource types in the IAM reference, so they can only
  # be granted on "*". They return public keys, key group membership and monitoring
  # settings: nothing secret.
  statement {
    sid = "CloudFrontUnscopedRead"
    actions = [
      "cloudfront:GetKeyGroup",
      "cloudfront:GetKeyGroupConfig",
      "cloudfront:GetMonitoringSubscription",
      "cloudfront:GetPublicKey",
      "cloudfront:GetPublicKeyConfig",
    ]
    resources = ["*"]
  }

  # Route 53 ARNs carry no account ID; the account is dedicated to this project.
  statement {
    sid = "DnsRead"
    actions = [
      "route53:Get*",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = [
      "arn:${local.partition}:route53:::hostedzone/*",
      "arn:${local.partition}:route53:::change/*",
    ]
  }

  # Table descriptions only: no GetItem, Query or Scan, so no visitor emails or tokens.
  statement {
    sid = "TableRead"
    actions = [
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:GetResourcePolicy",
      "dynamodb:ListTagsOfResource",
    ]
    resources = ["arn:${local.partition}:dynamodb:${local.regional_prefix}:table/${var.project}-*"]
  }

  # GetFunction also returns the environment, including the API origin secret. That
  # secret is in Terraform state too, which this role already reads.
  statement {
    sid = "FunctionRead"
    actions = [
      "lambda:GetFunction",
      "lambda:GetFunctionCodeSigningConfig",
      "lambda:GetFunctionConfiguration",
      "lambda:GetFunctionRecursionConfig",
      "lambda:GetPolicy",
      "lambda:ListTags",
      "lambda:ListVersionsByFunction",
    ]
    resources = ["arn:${local.partition}:lambda:${local.regional_prefix}:function:${var.project}-*"]
  }

  statement {
    sid       = "LogGroupList"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["arn:${local.partition}:logs:${local.regional_prefix}:log-group:*"]
  }

  statement {
    sid     = "LogGroupRead"
    actions = ["logs:ListTagsForResource", "logs:ListTagsLogGroup"]
    resources = [
      "arn:${local.partition}:logs:${local.regional_prefix}:log-group:/aws/lambda/${var.project}-*",
      "arn:${local.partition}:logs:${local.regional_prefix}:log-group:/aws/apigateway/${var.project}-*",
    ]
  }

  statement {
    sid     = "ApiRead"
    actions = ["apigateway:GET"]
    resources = [
      "arn:${local.partition}:apigateway:${local.region}::/apis",
      "arn:${local.partition}:apigateway:${local.region}::/apis/*",
      "arn:${local.partition}:apigateway:${local.region}::/tags/*",
    ]
  }

  statement {
    sid       = "MailIdentityRead"
    actions   = ["ses:GetEmailIdentity", "ses:ListTagsForResource"]
    resources = ["arn:${local.partition}:ses:${local.regional_prefix}:identity/*"]
  }

  # Subscription ARNs start with their topic's ARN, so this covers both.
  statement {
    sid = "AlertsRead"
    actions = [
      "sns:GetSubscriptionAttributes",
      "sns:GetTopicAttributes",
      "sns:ListTagsForResource",
      "pipes:DescribePipe",
      "pipes:ListTagsForResource",
    ]
    resources = [
      "arn:${local.partition}:sns:${local.regional_prefix}:${var.project}-*",
      "arn:${local.partition}:pipes:${local.regional_prefix}:pipe/${var.project}-*",
    ]
  }

  statement {
    sid       = "BudgetRead"
    actions   = ["budgets:ViewBudget", "budgets:ListTagsForResource"]
    resources = ["arn:${local.partition}:budgets::${local.account_id}:budget/${var.project}-*"]
  }
}

resource "aws_iam_role_policy" "plan" {
  name   = "terraform-plan-read"
  role   = aws_iam_role.plan.id
  policy = data.aws_iam_policy_document.plan.json
}

# --- Site deploy role: pushes to main on the infra repo only ---------------------------

data "aws_iam_policy_document" "site_deploy_trust" {
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

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["${local.infra_repo_subject}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "site_deploy" {
  name                 = "${var.project}-gha-site-deploy"
  description          = "Assumed by GitHub Actions on main to sync public site content and invalidate CloudFront."
  assume_role_policy   = data.aws_iam_policy_document.site_deploy_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "site_deploy" {
  statement {
    sid       = "List"
    actions   = ["s3:ListBucket"]
    resources = [var.site_bucket_arn]
  }

  statement {
    sid       = "WritePublicContent"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.site_bucket_arn}/*"]
  }

  # faces/ belongs to the face pipeline. The workflow already excludes it; this makes
  # that a guarantee rather than a convention. Role pages are in a separate bucket.
  statement {
    sid       = "ProtectFaces"
    effect    = "Deny"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.site_bucket_arn}/faces/*"]
  }

  statement {
    sid       = "Invalidate"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [var.distribution_arn]
  }
}

resource "aws_iam_role_policy" "site_deploy" {
  name   = "site-deploy"
  role   = aws_iam_role.site_deploy.id
  policy = data.aws_iam_policy_document.site_deploy.json
}

# --- Content deploy role: pushes to main on the private content repo only -------------

data "aws_iam_policy_document" "content_deploy_trust" {
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

    condition {
      test     = "StringEquals"
      variable = "${local.github_oidc_host}:sub"
      values   = ["${local.content_repo_subject}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "content_deploy" {
  name                 = "${var.project}-gha-content-deploy"
  description          = "Assumed by GitHub Actions on the private content repo's main branch to publish role write-ups."
  assume_role_policy   = data.aws_iam_policy_document.content_deploy_trust.json
  max_session_duration = 3600
}

data "aws_iam_policy_document" "content_deploy" {
  statement {
    sid       = "List"
    actions   = ["s3:ListBucket"]
    resources = [var.roles_bucket_arn]
  }

  statement {
    sid       = "WriteRolePages"
    actions   = ["s3:PutObject", "s3:DeleteObject"]
    resources = ["${var.roles_bucket_arn}/roles/*"]
  }

  statement {
    sid       = "Invalidate"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [var.distribution_arn]
  }
}

resource "aws_iam_role_policy" "content_deploy" {
  name   = "content-deploy"
  role   = aws_iam_role.content_deploy.id
  policy = data.aws_iam_policy_document.content_deploy.json
}
