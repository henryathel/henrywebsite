variable "project" {
  description = "Name prefix for resources."
  type        = string
}

variable "domain_name" {
  description = "Apex domain, named in the alert text."
  type        = string
}

variable "notification_email" {
  description = "Address that receives new-visitor and budget alerts. Kept out of the public repo."
  type        = string
  sensitive   = true
}

variable "monthly_budget_usd" {
  description = "Monthly AWS cost that triggers budget alerts."
  type        = number
}

variable "visitors_stream_arn" {
  description = "DynamoDB stream of the visitor log."
  type        = string
}
