# Decisions

Short records of significant choices and why. Newest last.

## 1. Protected content lives in a separate private repository

The infrastructure repo is public so the engineering can be read as a portfolio piece.
Committing the `/roles/*` write-ups there would publish the content the sign-in exists to
protect, so they live in a private `henrywebsite-content` repo. Its own workflow syncs them
to `roles/` in the site bucket using an OIDC role that can only write that prefix. The
public repo holds only placeholder role pages, and its deploy excludes `roles/*`.

## 2. Terraform is applied locally, never from CI

Only Henry applies infrastructure. CI runs `fmt`, `validate`, `plan` and checkov on pull
requests, and deploys static content on merge, but holds no role that can change
infrastructure. This keeps the most powerful credentials off GitHub entirely, which matters
more because the AWS account also hosts other personal projects. The cost is that `main`
can drift ahead of what is deployed; the habit is to apply straight after merging.

## 3. Plan role uses scoped read permissions, not ReadOnlyAccess

The AWS-managed `ReadOnlyAccess` policy would let any pull-request workflow read other
projects' S3 objects and configuration in the same account. The plan role instead gets
read actions per resource type, limited to `henrywebsite-*` ARNs, and gains permissions as
later modules add resources. Only pull requests from the repo itself can assume it: fork
PRs receive no OIDC token under the `pull_request` trigger.

## 4. S3 native state locking

Terraform 1.10+ can lock state with a lock file in the S3 bucket (`use_lockfile`), so there
is no DynamoDB lock table to create, pay for or explain. CI plans with `-lock=false` so the
plan role needs no write access to the state bucket.

## 5. State bucket created by a separate bootstrap stack

The state bucket must exist before any configuration can use it as a backend. `bootstrap/`
creates it with local state, which is then migrated into the bucket itself. The bucket is
versioned, SSE-S3 encrypted (a KMS key would add a monthly charge for no practical gain
here), blocks public access, denies non-TLS requests, and expires old state versions after
90 days.

## 6. Checkov rather than tfsec

tfsec has been folded into Trivy and is no longer developed on its own. Checkov covers both
Terraform and GitHub Actions workflows. Skipped checks are suppressed inline with a reason.

## 7. Actions pinned to commit SHAs

Third-party actions are pinned to full commit SHAs, with the version in a comment, so a
moved tag can't change what runs. Dependabot proposes updates monthly. Every job starts
from `permissions: {}` and requests only what it needs; only jobs that call AWS get
`id-token: write`.

## 8. Region is eu-north-1, not eu-west-2

The site runs in its own account within Henry's AWS Organization. An org-wide region
restriction SCP fully allows only `eu-north-1`; `us-east-1` is limited to global services
(CloudFront, IAM, ACM, Route 53, Budgets) and every other region is denied. Rather than
loosen a policy that also protects other accounts, the site works within it: regional
resources go in `eu-north-1`, and the CloudFront certificate in `us-east-1`. Pages are
served from CloudFront edge locations, so the region only adds a few tens of milliseconds
to the sign-in API calls from the UK, and data stays in the EU. One consequence: the random
face must use a CloudFront Function, because Lambda@Edge needs Lambda in `us-east-1`.

## 9. Human access: account access app, `aws login`, no long-lived keys

The organization was created by an AWS-managed setup that runs IAM Identity Center with
permission sets disabled. Instead, an "AWS account access" application signs users in to
each account by assuming a role there that trusts `account-access.amazonaws.com`. The site
account was created directly through Organizations, so it lacked that role; it was created
by hand as `henrywebsite-sso-admin` (AdministratorAccess, trusted only by that service).
This is the one IAM resource in the account not created by Terraform, because Terraform
cannot run before someone can sign in.

The AWS CLI's `configure sso` cannot see accounts granted this way, so CLI credentials come
from `aws login` (CLI 2.32+), which turns the console session into short-lived credentials.
No IAM users or access keys exist in the account. Member-account root credentials are
managed centrally by the organization and are deleted.
