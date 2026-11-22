variable "project" {
  description = "Name prefix for resources."
  type        = string
}

variable "domain_name" {
  description = "Apex domain. The site is served at www.<domain_name>; the apex redirects there."
  type        = string
}
