variable "project" {
  description = "Name prefix; IAM permissions are scoped to resources carrying it."
  type        = string
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repositories."
  type        = string
}

variable "infra_repo" {
  description = "Repository whose pull requests may assume the plan role."
  type        = string
}

variable "state_bucket_name" {
  description = "S3 bucket holding Terraform state."
  type        = string
}

variable "github_oidc_provider_arn" {
  description = "ARN of an existing GitHub Actions OIDC provider. Null creates one (only one is allowed per account)."
  type        = string
  default     = null
}
