variable "project" {
  description = "Name prefix; IAM permissions are scoped to resources carrying it."
  type        = string
}

variable "github_owner" {
  description = "GitHub user or organisation that owns the repositories."
  type        = string
}

variable "github_owner_id" {
  description = "Numeric ID of the GitHub owner; part of the immutable OIDC subject."
  type        = number
}

variable "infra_repo" {
  description = "Repository whose pull requests may assume the plan role."
  type        = string
}

variable "infra_repo_id" {
  description = "Numeric ID of the infra repository; part of the immutable OIDC subject."
  type        = number
}

variable "content_repo" {
  description = "Private repository holding the role write-ups; its main branch may assume the content deploy role."
  type        = string
}

variable "content_repo_id" {
  description = "Numeric ID of the content repository; part of the immutable OIDC subject."
  type        = number
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

variable "site_bucket_arn" {
  description = "ARN of the site bucket the deploy role writes to."
  type        = string
}

variable "distribution_arn" {
  description = "ARN of the CloudFront distribution the deploy role may invalidate."
  type        = string
}

variable "roles_bucket_arn" {
  description = "ARN of the bucket holding the protected role write-ups."
  type        = string
}
