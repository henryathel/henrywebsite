variable "project" {
  description = "Name prefix for resources."
  type        = string
}

variable "domain_name" {
  description = "Apex domain. The site is served at www.<domain_name>; the apex redirects there."
  type        = string
}

variable "api_domain" {
  description = "execute-api hostname of the auth API, the origin for /api/*."
  type        = string
}

variable "api_origin_secret" {
  description = "Value of the X-Origin-Verify header CloudFront sends to the auth API."
  type        = string
  sensitive   = true
}

variable "roles_key_group_id" {
  description = "CloudFront key group whose signed cookies unlock /roles/*."
  type        = string
}
