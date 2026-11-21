# henrywebsite

Infrastructure and public pages for Henry Ashton's career site: S3 + CloudFront, an email
magic-link sign-in for detailed role pages, and a GAN-generated face that changes on every
load. All infrastructure is Terraform; see `docs/decisions.md` for the reasoning.

## Layout

| Path | What |
| --- | --- |
| `bootstrap/` | One-off stack creating the Terraform state bucket |
| `infra/` | Root module; `infra/modules/{ci,site,auth,faces}` |
| `lambdas/` | Python auth Lambdas (step 3) |
| `site/` | Public pages and placeholder role pages |
| `.github/workflows/` | `pr.yml` (checks and plan), `deploy.yml` (site content) |

Real role write-ups are kept in the private `henrywebsite-content` repository.

## First-time setup

Needs AWS credentials with admin rights in your shell, Terraform 1.17.

1. **State bucket**

   ```sh
   cd bootstrap
   terraform init && terraform apply
   ```

   Then move bootstrap's own state into the bucket. Add this block to `bootstrap/main.tf`
   (and commit it), create `infra/backend.hcl` as in step 2, run
   `terraform init -migrate-state -backend-config=../infra/backend.hcl`, and delete the
   local `terraform.tfstate*` files.

   ```hcl
   terraform {
     backend "s3" {
       key          = "bootstrap/terraform.tfstate"
       region       = "eu-west-2"
       encrypt      = true
       use_lockfile = true
     }
   }
   ```

2. **Infrastructure**

   ```sh
   cd infra
   cp backend.hcl.example backend.hcl   # fill in the bucket name
   terraform init -backend-config=backend.hcl
   terraform apply
   ```

   If the account already has a GitHub OIDC provider, pass
   `-var github_oidc_provider_arn=<arn>` instead of creating a second one.

3. **GitHub repository variables** (Settings → Secrets and variables → Actions → Variables)

   - `AWS_PLAN_ROLE_ARN`: the `plan_role_arn` output
   - `TF_STATE_BUCKET`: the bootstrap `state_bucket_name` output

## Day to day

Open a PR: CI checks formatting, validates, plans and runs checkov. Merge, then run
`terraform apply` in `infra/` locally. CI never applies infrastructure.
