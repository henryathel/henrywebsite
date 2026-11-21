# The bucket name contains the account ID, so it is supplied at init time rather than
# committed: `terraform init -backend-config=backend.hcl` locally (see backend.hcl.example),
# or `-backend-config="bucket=..."` in CI.
terraform {
  backend "s3" {
    key          = "infra/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
