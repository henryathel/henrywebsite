variable "project" {
  description = "Name prefix for resources."
  type        = string
}

variable "domain_name" {
  description = "Apex domain. Mail is sent from it; links point at www.<domain_name>."
  type        = string
}

variable "zone_id" {
  description = "Route 53 hosted zone for the domain, for the SES verification records."
  type        = string
}

variable "lambda_package" {
  description = "Path to the zip built by lambdas/build.py."
  type        = string
}

variable "signing_public_key_pem" {
  description = "Public half of the cookie-signing key pair, created by scripts/create-signing-key.sh."
  type        = string
}

variable "signing_key_parameter" {
  description = "SSM SecureString parameter holding the private signing key. Created outside Terraform so the key never enters state."
  type        = string
}

variable "token_ttl_minutes" {
  description = "How long an emailed sign-in link stays valid."
  type        = number
}

variable "cookie_ttl_days" {
  description = "How long the signed cookies for /roles/* last."
  type        = number
}

variable "ses_test_recipients" {
  description = "Addresses to verify in SES so they can receive mail while the account is in the SES sandbox."
  type        = set(string)
  default     = []
}
