variable "project" {
  description = "Name prefix for all resources in this project."
  type        = string
  default     = "henrywebsite"
}

variable "region" {
  description = "AWS region for the state bucket."
  type        = string
  default     = "eu-west-2"
}
