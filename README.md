# henrywebsite

Infrastructure and public pages for Henry Ashton's career site: S3 + CloudFront, an email
emailed-code sign-in for detailed role pages, and an AI-generated face that changes on every
load. All infrastructure is Terraform; see `docs/decisions.md` for the reasoning.

## Layout

| Path | What |
| --- | --- |
| `bootstrap/` | One-off stack creating the Terraform state bucket |
| `infra/` | Root module; `infra/modules/{ci,site,auth,faces}` |
| `lambdas/` | Python auth Lambdas; `build.py` makes the deployment zip |
| `scripts/` | One-off helpers: the cookie-signing key, face uploads, the link-preview image |
| `site/` | Public pages and placeholder role pages |
| `.github/workflows/` | `pr.yml` (checks and plan), `deploy.yml` (site content) |

Real role write-ups are kept in the private `henrywebsite-content` repository.

## First-time setup

Needs Terraform 1.17, Python 3.12 and AWS CLI 2.32+. Sign in with `aws login --profile henrywebsite`
(see `docs/decisions.md` #9), and run Terraform with `AWS_PROFILE=henrywebsite`.

1. **State bucket.** `bootstrap/main.tf` already declares the S3 backend, which can't be
   used until the bucket exists. On a brand-new account, comment out the `backend "s3"`
   block, then:

   ```sh
   cd bootstrap
   terraform init && terraform apply
   ```

   Restore the block, create `infra/backend.hcl` as in step 2, and move the state into
   the bucket:

   ```sh
   terraform init -migrate-state -backend-config=../infra/backend.hcl
   rm terraform.tfstate terraform.tfstate.backup
   ```

   Afterwards, `bootstrap/` is used like any other stack:
   `terraform init -backend-config=../infra/backend.hcl`.

2. **Infrastructure**

   Create the cookie-signing key once. The private key goes straight into SSM; commit the
   public key it writes to `infra/keys/` (see `docs/decisions.md` #16):

   ```sh
   AWS_PROFILE=henrywebsite scripts/create-signing-key.sh
   ```

   Build the Lambda package. Terraform hashes it, so rebuild before every plan or apply:

   ```sh
   (cd lambdas && python3.12 build.py)
   ```

   Then:

   ```sh
   cd infra
   cp backend.hcl.example backend.hcl   # fill in the bucket name
   terraform init -backend-config=backend.hcl
   terraform apply
   ```

   If the account already has a GitHub OIDC provider, pass
   `-var github_oidc_provider_arn=<arn>` instead of creating a second one.

   The certificate can't validate until the domain's DNS points at Route 53, so the first
   apply happens in two stages:

   ```sh
   terraform apply -target=module.site.aws_route53_zone.this
   terraform output name_servers
   ```

   At Namecheap: **Domain List** → the domain → **Manage** → **Nameservers** → **Custom
   DNS**, and enter the four nameservers. Wait until
   `dig +short NS henryashton.dev @1.1.1.1` returns them, then run the full
   `terraform apply`. ACM validation and the CloudFront distribution each take several
   minutes.

   While SES is in its sandbox, sign-in mail only reaches verified addresses. To test,
   list yours in `infra/terraform.tfvars` (git-ignored) and click the link SES emails to verify it:

   ```hcl
   ses_test_recipients = ["you@example.com"]
   ```

   For real visitors, request SES production access (SES console in `eu-north-1` →
   **Account dashboard** → **Request production access**).

3. **GitHub repository variables** (Settings → Secrets and variables → Actions → Variables)

   - `AWS_PLAN_ROLE_ARN`: the `plan_role_arn` output
   - `TF_STATE_BUCKET`: the bootstrap `state_bucket_name` output
   - `AWS_SITE_DEPLOY_ROLE_ARN`: the `site_deploy_role_arn` output
   - `SITE_BUCKET`: the `site_bucket` output
   - `CLOUDFRONT_DISTRIBUTION_ID`: the `cloudfront_distribution_id` output

   In the private `henrywebsite-content` repository:

   - `AWS_CONTENT_DEPLOY_ROLE_ARN`: the `content_deploy_role_arn` output
   - `ROLES_BUCKET`: the `roles_bucket` output
   - `CLOUDFRONT_DISTRIBUTION_ID`: as above

4. **Face pool** (a placeholder shows until it exists). Generate the faces with FLUX.1
   [schnell] on Replicate, using an API token from replicate.com (Account settings → API
   tokens). Keep the output outside the repo:

   ```sh
   REPLICATE_API_TOKEN=... scripts/generate-faces.py ~/faces --count 300
   ```

   Look through `~/faces` and delete any face that is distorted or odd; the upload
   renumbers what is left. Then:

   ```sh
   AWS_PROFILE=henrywebsite scripts/upload-faces.sh ~/faces
   cd infra && terraform apply
   ```

   The script renumbers them `faces/000.jpg` onward; the apply tells the random-face
   function how many there are (`docs/decisions.md` #23). Repeat both to replace the pool.

## Day to day

Open a PR: CI checks formatting, validates, plans and runs checkov, and lints, type-checks
and tests the Lambdas. Merge, then build the Lambda package and run `terraform apply` in
`infra/` locally. CI never applies infrastructure.

Lambda development, from `lambdas/`:

```sh
uv venv -p 3.12 && uv pip install -r requirements-dev.txt
.venv/bin/pytest && .venv/bin/mypy && .venv/bin/ruff check .
```

After changing dependencies in `pyproject.toml`, regenerate both lock files:

```sh
uv pip compile pyproject.toml --python-platform aarch64-manylinux2014 --python-version 3.12 --generate-hashes --no-header -o requirements.txt
uv pip compile pyproject.toml --extra dev --python-version 3.12 --universal --no-header -o requirements-dev.txt
```
