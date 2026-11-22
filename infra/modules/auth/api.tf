# HTTP API reached only through CloudFront at /api/*. CloudFront adds a secret header
# that the functions check, so calling the execute-api URL directly gets a 403; this also
# makes CloudFront's viewer-address header, used for per-IP rate limits, trustworthy.

resource "random_password" "origin_secret" {
  length  = 48
  special = false
}

resource "aws_apigatewayv2_api" "auth" {
  name          = "${var.project}-auth"
  description   = "Sign-in API, served under /api/* on the site's distribution"
  protocol_type = "HTTP"
}

resource "aws_cloudwatch_log_group" "api" {
  #checkov:skip=CKV_AWS_158:Access logs hold no secrets (no query strings); the default encryption is enough.
  #checkov:skip=CKV_AWS_338:30 days is enough to investigate abuse.
  name              = "/aws/apigateway/${var.project}-auth"
  retention_in_days = 30
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.auth.id
  name        = "$default"
  auto_deploy = true

  # A ceiling on cost and abuse across all callers, below the per-email and per-IP limits.
  default_route_settings {
    throttling_burst_limit = 10
    throttling_rate_limit  = 5
  }

  # $context.path excludes the query string, so sign-in tokens never reach the logs.
  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.api.arn
    format = jsonencode({
      requestId = "$context.requestId"
      time      = "$context.requestTime"
      method    = "$context.httpMethod"
      path      = "$context.path"
      status    = "$context.status"
      latencyMs = "$context.responseLatency"
      error     = "$context.integrationErrorMessage"
    })
  }
}

locals {
  routes = {
    "POST /api/auth/request" = "request"
    "GET /api/auth/verify"   = "verify"
    "POST /api/auth/verify"  = "verify"
  }
}

resource "aws_apigatewayv2_integration" "auth" {
  for_each = local.functions

  api_id                 = aws_apigatewayv2_api.auth.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.auth[each.key].invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "auth" {
  #checkov:skip=CKV_AWS_309:Public sign-in endpoints by design; access is controlled by the origin secret and rate limits.
  for_each = local.routes

  api_id    = aws_apigatewayv2_api.auth.id
  route_key = each.key
  target    = "integrations/${aws_apigatewayv2_integration.auth[each.value].id}"
}

resource "aws_lambda_permission" "api" {
  for_each = local.functions

  statement_id  = "AllowApiGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.auth[each.key].function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.auth.execution_arn}/*/*/api/auth/${each.key}"
}
