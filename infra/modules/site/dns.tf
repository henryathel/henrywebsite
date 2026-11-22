locals {
  www_domain = "www.${var.domain_name}"
}

# The domain is registered at Namecheap and delegated here by setting Route 53's
# nameservers there, so every record lives in Terraform.
resource "aws_route53_zone" "this" {
  #checkov:skip=CKV2_AWS_38:DNSSEC needs an asymmetric KMS key in us-east-1 (monthly charge); revisit later.
  #checkov:skip=CKV2_AWS_39:Query logging adds cost and isn't needed for a personal site.
  name    = var.domain_name
  comment = "${var.project}: managed by Terraform"
}

# Only Amazon may issue certificates for this domain, and nobody may issue wildcards.
resource "aws_route53_record" "caa" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "CAA"
  ttl     = 3600
  records = [
    "0 issue \"amazon.com\"",
    "0 issuewild \";\"",
  ]
}

# The domain receives no mail. A null MX (RFC 7505), SPF -all and DMARC reject tell other
# servers to refuse mail claiming to be from it. SES sign-in mail (step 3) still passes
# DMARC through DKIM alignment.
resource "aws_route53_record" "null_mx" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "MX"
  ttl     = 3600
  records = ["0 ."]
}

resource "aws_route53_record" "spf" {
  zone_id = aws_route53_zone.this.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 3600
  records = ["v=spf1 -all"]
}

resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.this.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 3600
  records = ["v=DMARC1; p=reject; adkim=s; aspf=s"]
}

# Both names alias the one distribution; its viewer-request function redirects the apex.
resource "aws_route53_record" "site" {
  for_each = {
    for pair in setproduct([var.domain_name, local.www_domain], ["A", "AAAA"]) :
    "${pair[0]}-${pair[1]}" => { name = pair[0], type = pair[1] }
  }

  zone_id = aws_route53_zone.this.zone_id
  name    = each.value.name
  type    = each.value.type

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}
