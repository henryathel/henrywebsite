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

The trust policy matches GitHub's immutable subject format
(`repo:<owner>@<owner-id>/<repo>@<repo-id>:pull_request`), which GitHub uses for this
repository. Pinning numeric IDs means a deleted and re-created repo with the same name
cannot assume the role.

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

## 10. DNS delegated from Namecheap to Route 53

The domain stays registered at Namecheap, but its nameservers point at a Route 53 hosted
zone, so every record is in Terraform: certificate validation, the CloudFront aliases, and
later the SES DKIM records. Route 53 alias records also let the bare domain point at
CloudFront, which a CNAME can't. Cost is $0.50 a month. The zone adds a CAA record (only
Amazon may issue certificates) and, because the domain receives no mail, a null MX,
`v=spf1 -all` and DMARC `p=reject` so nobody can convincingly send mail as it. SES mail in
step 3 still passes DMARC through DKIM.

## 11. One distribution for both names; apex redirected by a CloudFront Function

`www.henryashton.dev` is canonical. Rather than a second distribution or an S3 website
bucket for the redirect, both names are aliases of one distribution and a viewer-request
CloudFront Function returns a 301 for the apex, keeping the path and query string. The
same function maps `/dir/` to `/dir/index.html`, which a private S3 origin doesn't do on
its own. CloudFront Functions cost a fraction of Lambda@Edge, and Lambda@Edge isn't
allowed by the org SCP anyway (decision 8).

## 12. CloudFront may list the bucket, so missing pages are 404s

With only `s3:GetObject`, S3 answers 403 for a missing object. Step 3 maps 403 to the
login page for `/roles/*`, and CloudFront error responses apply to the whole distribution,
so every missing page would wrongly show the login page. Granting CloudFront
`s3:ListBucket` makes missing objects 404s, which get a 404 page, and leaves 403 meaning
"not signed in".

## 13. Real role content isn't published until `/roles/*` is protected

The private content repo's deploy workflow and role arrive in step 3, together with the
signed-cookie protection. Until then nothing writes to `roles/`, and the public deploy role
is explicitly denied `roles/*` and `faces/*` in IAM, not just excluded in the workflow.
