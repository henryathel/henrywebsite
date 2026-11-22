variable "project" {
  description = "Name prefix for all resources in this project."
  type        = string
  default     = "henrywebsite"
}

variable "region" {
  description = "Primary AWS region."
  type        = string
  default     = "eu-north-1"
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repositories."
  type        = string
  default     = "henryathel"
}

variable "infra_repo" {
  description = "Public repository holding this infrastructure and the public pages."
  type        = string
  default     = "henrywebsite"
}

variable "github_oidc_provider_arn" {
  description = "ARN of an existing GitHub Actions OIDC provider in this account. Leave null to create one."
  type        = string
  default     = null
}
