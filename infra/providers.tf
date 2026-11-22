locals {
  default_tags = {
    Project   = var.project
    ManagedBy = "terraform"
    Stack     = "infra"
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = local.default_tags
  }
}

# CloudFront only accepts ACM certificates from us-east-1. The org SCP allows global
# services (ACM, CloudFront, Route 53, IAM) there but no regional ones.
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"

  default_tags {
    tags = local.default_tags
  }
}
