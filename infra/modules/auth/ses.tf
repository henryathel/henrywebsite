# Sign-in links are sent as signin@<domain>. Easy DKIM signs each message with the domain,
# which is what lets the mail pass the zone's strict DMARC policy (adkim=s).

locals {
  sender_address   = "signin@${var.domain_name}"
  mail_from_domain = "mail.${var.domain_name}"
}

resource "aws_sesv2_email_identity" "domain" {
  email_identity = var.domain_name

  dkim_signing_attributes {
    next_signing_key_length = "RSA_2048_BIT"
  }
}

resource "aws_route53_record" "dkim" {
  count = 3

  zone_id = var.zone_id
  name    = "${aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens[count.index]}._domainkey.${var.domain_name}"
  type    = "CNAME"
  ttl     = 3600
  records = ["${aws_sesv2_email_identity.domain.dkim_signing_attributes[0].tokens[count.index]}.dkim.amazonses.com"]
}

# A custom MAIL FROM domain makes the envelope sender a subdomain of ours, so SPF aligns
# too, and bounces go to SES rather than to the apex, which has a null MX.
resource "aws_sesv2_email_identity_mail_from_attributes" "domain" {
  email_identity         = aws_sesv2_email_identity.domain.email_identity
  mail_from_domain       = local.mail_from_domain
  behavior_on_mx_failure = "REJECT_MESSAGE"
}

resource "aws_route53_record" "mail_from_mx" {
  zone_id = var.zone_id
  name    = local.mail_from_domain
  type    = "MX"
  ttl     = 3600
  records = ["10 feedback-smtp.${data.aws_region.current.region}.amazonses.com"]
}

resource "aws_route53_record" "mail_from_spf" {
  zone_id = var.zone_id
  name    = local.mail_from_domain
  type    = "TXT"
  ttl     = 3600
  records = ["v=spf1 include:amazonses.com -all"]
}

# Sandbox only: SES sends a confirmation email to each address, which must be clicked.
resource "aws_sesv2_email_identity" "test_recipient" {
  for_each = var.ses_test_recipients

  email_identity = each.value
}
