locals {
  s3_origin_id    = "site-bucket"
  roles_origin_id = "roles-bucket"
  api_origin_id   = "auth-api"

  # AWS-managed cache policies, referenced by ID rather than a data source so `plan`
  # needs no extra CloudFront read permissions.
  caching_optimized_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
  caching_disabled_policy_id  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
}

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${var.project}-site"
  description                       = "CloudFront access to the private site bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "viewer_request" {
  name    = "${var.project}-viewer-request"
  comment = "Apex to www redirect, /roles redirect and index.html rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code = templatefile("${path.module}/functions/viewer-request.js", {
    apex_domain      = var.domain_name
    canonical_domain = local.www_domain
  })
}

# Two policies with the same security headers; the second also keeps search engines out
# of the sign-in pages, the API and the protected write-ups.
locals {
  response_headers_policies = {
    security = { name = "${var.project}-security-headers", noindex = false }
    noindex  = { name = "${var.project}-security-headers-noindex", noindex = true }
  }
}

resource "aws_cloudfront_response_headers_policy" "this" {
  for_each = local.response_headers_policies

  name    = each.value.name
  comment = each.value.noindex ? "Security headers plus X-Robots-Tag: noindex" : "Security headers for every response"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 63072000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }

    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    content_security_policy {
      content_security_policy = join("; ", [
        "default-src 'self'",
        "img-src 'self' data:",
        "style-src 'self'",
        "script-src 'self'",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'",
        "upgrade-insecure-requests",
      ])
      override = true
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = "camera=(), microphone=(), geolocation=(), interest-cohort=()"
      override = true
    }

    dynamic "items" {
      for_each = each.value.noindex ? [1] : []

      content {
        header   = "X-Robots-Tag"
        value    = "noindex, nofollow"
        override = true
      }
    }
  }
}

moved {
  from = aws_cloudfront_response_headers_policy.security
  to   = aws_cloudfront_response_headers_policy.this["security"]
}

# Only what the auth API uses: the form body's content type, the query string (the
# verify token), and the viewer's IP address for rate limiting. No cookies.
resource "aws_cloudfront_origin_request_policy" "api" {
  name    = "${var.project}-auth-api"
  comment = "Forward to the auth API only what it reads"

  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["CloudFront-Viewer-Address", "Content-Type"]
    }
  }

  query_strings_config {
    query_string_behavior = "all"
  }

  cookies_config {
    cookie_behavior = "none"
  }
}

resource "aws_cloudfront_distribution" "site" {
  #checkov:skip=CKV_AWS_68:WAF costs at least ~$6/month; a static site with a rate-limited API doesn't justify it yet.
  #checkov:skip=CKV2_AWS_47:Log4j WAF rule: no WAF (see CKV_AWS_68), and no Java anywhere.
  #checkov:skip=CKV_AWS_86:Access logging deferred; the visitor log covers who signed in.
  #checkov:skip=CKV_AWS_310:Origin failover needs a second bucket; not worth it for a personal site.
  #checkov:skip=CKV_AWS_374:Geo restriction would block legitimate recruiters.
  #checkov:skip=CKV2_AWS_32:Every behaviour attaches a response headers policy; checkov can't resolve the for_each reference.
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  comment             = "${var.project}: ${local.www_domain}"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = [local.www_domain, var.domain_name]

  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.this["site"].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  origin {
    origin_id                = local.roles_origin_id
    domain_name              = aws_s3_bucket.this["roles"].bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  origin {
    origin_id   = local.api_origin_id
    domain_name = var.api_domain

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = var.api_origin_secret
    }
  }

  default_cache_behavior {
    target_origin_id           = local.s3_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_optimized_policy_id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this["security"].id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_request.arn
    }
  }

  # Ordered behaviours are matched first to last, before the default.
  ordered_cache_behavior {
    path_pattern               = "/api/*"
    target_origin_id           = local.api_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_disabled_policy_id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.api.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this["noindex"].id
  }

  # The protected write-ups. CloudFront rejects any request without valid signed cookies
  # from the key group with a 403, before it reaches the cache or the bucket.
  ordered_cache_behavior {
    path_pattern               = "/roles/*"
    target_origin_id           = local.roles_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_optimized_policy_id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this["noindex"].id
    trusted_key_groups         = [var.roles_key_group_id]

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_request.arn
    }
  }

  # Public, but kept out of search results.
  ordered_cache_behavior {
    path_pattern               = "/login*"
    target_origin_id           = local.s3_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_optimized_policy_id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this["noindex"].id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_request.arn
    }
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  # Missing or invalid signed cookies on /roles/*. S3 can list both buckets, so a
  # missing object is a 404 and never lands here (docs/decisions.md #12).
  custom_error_response {
    error_code            = 403
    response_code         = 403
    response_page_path    = "/login.html"
    error_caching_min_ttl = 0
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.site.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}
