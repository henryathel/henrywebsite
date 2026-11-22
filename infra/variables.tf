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

variable "github_owner_id" {
  description = "Numeric ID of the GitHub owner (`gh api users/<owner> --jq .id`)."
  type        = number
  default     = 213582221
}

variable "infra_repo" {
  description = "Public repository holding this infrastructure and the public pages."
  type        = string
  default     = "henrywebsite"
}

variable "infra_repo_id" {
  description = "Numeric ID of the infra repository (`gh api repos/<owner>/<repo> --jq .id`)."
  type        = number
  default     = 1466927842
}

variable "content_repo" {
  description = "Private repository holding the role write-ups."
  type        = string
  default     = "henrywebsite-content"
}

variable "content_repo_id" {
  description = "Numeric ID of the content repository (`gh api repos/<owner>/<repo> --jq .id`)."
  type        = number
  default     = 1466928629
}

variable "github_oidc_provider_arn" {
  description = "ARN of an existing GitHub Actions OIDC provider in this account. Leave null to create one."
  type        = string
  default     = null
}

variable "domain_name" {
  description = "Apex domain; the site is served at www.<domain_name>."
  type        = string
  default     = "henryashton.dev"
}

variable "signing_key_parameter" {
  description = "SSM parameter holding the cookie-signing private key (scripts/create-signing-key.sh)."
  type        = string
  default     = "/henrywebsite/cookie-signing-key"
}

variable "code_ttl_minutes" {
  description = "How long an emailed sign-in code stays valid."
  type        = number
  default     = 10
}

variable "cookie_ttl_days" {
  description = "How long a sign-in lasts before the visitor must request a new code."
  type        = number
  default     = 5
}

variable "ses_test_recipients" {
  description = "Addresses that may receive sign-in mail while SES is in its sandbox. Set in terraform.tfvars (git-ignored)."
  type        = set(string)
  default     = []
}
