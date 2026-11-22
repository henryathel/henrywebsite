locals {
  s3_origin_id = "site-bucket"

  # AWS-managed cache policy "Managed-CachingOptimized". Referenced by ID rather than a
  # data source so `plan` needs no extra CloudFront read permissions.
  caching_optimized_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"
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
  comment = "Apex to www redirect and index.html rewrite"
  runtime = "cloudfront-js-2.0"
  publish = true
  code = templatefile("${path.module}/functions/viewer-request.js", {
    apex_domain      = var.domain_name
    canonical_domain = local.www_domain
  })
}

resource "aws_cloudfront_response_headers_policy" "security" {
  name    = "${var.project}-security-headers"
  comment = "Security headers for every response"

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
  }
}

resource "aws_cloudfront_distribution" "site" {
  #checkov:skip=CKV_AWS_68:WAF costs at least ~$6/month; a static site with a rate-limited API doesn't justify it yet.
  #checkov:skip=CKV2_AWS_47:Log4j WAF rule: no WAF (see CKV_AWS_68), and no Java anywhere.
  #checkov:skip=CKV_AWS_86:Access logging deferred; the visitor log covers who signed in.
  #checkov:skip=CKV_AWS_310:Origin failover needs a second bucket; not worth it for a personal site.
  #checkov:skip=CKV_AWS_374:Geo restriction would block legitimate recruiters.
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  comment             = "${var.project}: ${local.www_domain}"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = [local.www_domain, var.domain_name]

  origin {
    origin_id                = local.s3_origin_id
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = local.s3_origin_id
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.caching_optimized_policy_id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

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
