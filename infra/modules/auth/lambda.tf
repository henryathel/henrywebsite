data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  site_url = "https://www.${var.domain_name}"

  common_environment = {
    SITE_URL         = local.site_url
    ORIGIN_SECRET    = random_password.origin_secret.result
    CODES_TABLE      = aws_dynamodb_table.codes.name
    CODE_TTL_SECONDS = tostring(var.code_ttl_minutes * 60)
  }

  # Each function gets only the settings, and (below) the permissions, it uses.
  functions = {
    request = {
      handler     = "auth.request_code.handler"
      description = "POST /api/auth/request: email a six-digit sign-in code"
      policy      = data.aws_iam_policy_document.request.json
      environment = {
        RATE_LIMITS_TABLE = aws_dynamodb_table.rate_limits.name
        SENDER            = "Henry Ashton's website <${local.sender_address}>"
      }
    }
    verify = {
      handler     = "auth.verify_code.handler"
      description = "POST /api/auth/verify: exchange a sign-in code for signed cookies"
      policy      = data.aws_iam_policy_document.verify.json
      environment = {
        VISITORS_TABLE        = aws_dynamodb_table.visitors.name
        SIGNING_KEY_PARAMETER = var.signing_key_parameter
        KEY_PAIR_ID           = aws_cloudfront_public_key.cookie_signing.id
        COOKIE_TTL_SECONDS    = tostring(var.cookie_ttl_days * 86400)
      }
    }
  }

  log_group_arn_prefix = "arn:${data.aws_partition.current.partition}:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${var.project}-auth"
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "request" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${local.log_group_arn_prefix}-request:*"]
  }

  statement {
    sid       = "StoreCode"
    actions   = ["dynamodb:PutItem"]
    resources = [aws_dynamodb_table.codes.arn]
  }

  statement {
    sid       = "CountAttempts"
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.rate_limits.arn]
  }

  # Only from the sign-in address. In the SES sandbox, SES also authorises against each
  # recipient's identity, hence the test recipients.
  statement {
    sid     = "SendLink"
    actions = ["ses:SendEmail"]
    resources = concat(
      [aws_sesv2_email_identity.domain.arn],
      [for recipient in aws_sesv2_email_identity.test_recipient : recipient.arn],
    )

    condition {
      test     = "StringEquals"
      variable = "ses:FromAddress"
      values   = [local.sender_address]
    }
  }
}

data "aws_iam_policy_document" "verify" {
  statement {
    sid       = "Logs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${local.log_group_arn_prefix}-verify:*"]
  }

  # Count an attempt, then delete the code once it matches.
  statement {
    sid       = "UseCode"
    actions   = ["dynamodb:UpdateItem", "dynamodb:DeleteItem"]
    resources = [aws_dynamodb_table.codes.arn]
  }

  statement {
    sid       = "LogVisit"
    actions   = ["dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.visitors.arn]
  }

  # SecureString with the AWS-managed aws/ssm key, which SSM may use on the caller's behalf.
  statement {
    sid       = "ReadSigningKey"
    actions   = ["ssm:GetParameter"]
    resources = ["arn:${data.aws_partition.current.partition}:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${var.signing_key_parameter}"]
  }
}

resource "aws_iam_role" "function" {
  for_each = local.functions

  name               = "${var.project}-auth-${each.key}"
  description        = each.value.description
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy" "function" {
  for_each = local.functions

  name   = "${var.project}-auth-${each.key}"
  role   = aws_iam_role.function[each.key].id
  policy = each.value.policy
}

resource "aws_cloudwatch_log_group" "function" {
  #checkov:skip=CKV_AWS_158:Logs hold no secrets (emails are pseudonymised); the default encryption is enough.
  #checkov:skip=CKV_AWS_338:30 days is enough to debug sign-ins; the visitor log is the durable record.
  for_each = local.functions

  name              = "/aws/lambda/${var.project}-auth-${each.key}"
  retention_in_days = 30
}

resource "aws_lambda_function" "auth" {
  #checkov:skip=CKV_AWS_50:X-Ray tracing isn't worth its IAM and cost for two small functions; logs are structured.
  #checkov:skip=CKV_AWS_116:Invoked synchronously by API Gateway, so a dead-letter queue would never receive anything.
  #checkov:skip=CKV_AWS_117:No VPC: the functions only call AWS APIs, and a VPC would need NAT or endpoints.
  #checkov:skip=CKV_AWS_115:New accounts can't reserve concurrency; API Gateway throttling bounds load instead.
  #checkov:skip=CKV_AWS_173:Environment variables use the default Lambda encryption; the signing key isn't one of them.
  #checkov:skip=CKV_AWS_272:Code signing needs a Signer profile; the package is built reproducibly in CI instead.
  for_each = local.functions

  function_name    = "${var.project}-auth-${each.key}"
  description      = each.value.description
  role             = aws_iam_role.function[each.key].arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = each.value.handler
  filename         = var.lambda_package
  source_code_hash = filebase64sha256(var.lambda_package)
  memory_size      = 256
  timeout          = 10

  environment {
    variables = merge(local.common_environment, each.value.environment)
  }

  logging_config {
    log_format            = "JSON"
    log_group             = aws_cloudwatch_log_group.function[each.key].name
    application_log_level = "INFO"
    system_log_level      = "WARN"
  }

  depends_on = [aws_iam_role_policy.function]
}
