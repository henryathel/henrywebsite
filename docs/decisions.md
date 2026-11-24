# Decisions

Short records of significant choices and why. Newest last.

## 1. Protected content lives in a separate private repository

The infrastructure repo is public so the engineering can be read as a portfolio piece.
Committing the `/roles/*` write-ups there would publish the content the sign-in exists to
protect, so they live in a private `henrywebsite-content` repo. Its own workflow syncs them
to a separate roles bucket (#14) using an OIDC role that can only write `roles/` there. The
public repo holds only placeholder role pages, which are never deployed.

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

The private content repo's deploy role arrived in step 3, together with the signed-cookie
protection, so nothing could publish role pages before they were protected.

## 14. Role pages live in their own bucket

The `/roles/*` behaviour requires signed cookies, but CloudFront picks a behaviour from the
path as received, and the default behaviour's function then rewrites paths (`/roles` would
become `/roles/index.html`). If role pages shared the public bucket, any path that reached
the default behaviour but resolved to a `roles/` key in S3 would serve them without a
cookie. Instead they live in a separate private bucket that is the origin only for
`/roles/*`. No path through any other behaviour can reach it, so protection doesn't depend
on getting path matching exactly right. It also gives each deploy role one bucket to write
to.

## 15. The emailed link confirms with a button; only the POST uses the token

_Superseded by #21: sign-in now uses a code, so there is no link to prefetch._

The brief had `GET /api/auth/verify` consume the token. Many corporate mail filters (such
as Microsoft Defender Safe Links) fetch every link in an incoming email to scan it, which
would use up a single-use link before a recruiter clicked it. So GET only returns a page
with a "Sign in" button. That button POSTs the token, and only the POST deletes it,
sets the cookies and logs the visit. The token is consumed by a conditional `DeleteItem`
(`attribute_exists AND expires_at > now`), so it works once even when two requests race.
Expiry is checked in that condition because DynamoDB TTL deletes items only eventually.

## 16. The cookie-signing key is created outside Terraform

Terraform stores resource values in state, which the plan role can read. A
`tls_private_key` resource would put the signing key there. Instead,
`scripts/create-signing-key.sh` generates the key pair locally and writes the private key
straight to an SSM SecureString, then deletes it; only the public key is committed and
managed by Terraform (CloudFront public key and key group). The verify function reads the
parameter once per container. The parameter is the one auth resource Terraform doesn't
manage, deliberately. Signatures are RSA with SHA-1 because that is what CloudFront
verifies; SHA-1's weakness is collisions, which don't help forge a signature over a policy
we chose.

## 17. API reachable only through CloudFront, checked by a secret header

The HTTP API's execute-api URL is public. CloudFront adds an `X-Origin-Verify` header with
a random value, and both functions return 403 without it. Besides stopping direct calls,
this makes the `CloudFront-Viewer-Address` header trustworthy: per-IP rate limits rely on
it, and anyone could forge it on a direct call. The value is in Terraform state and the
function environment; that's acceptable because it only gates rate-limit bypass, not
access to content. A Lambda authorizer or WAF would cost more for the same effect.

## 18. Rate limits: DynamoDB counters plus API Gateway throttling

Each code request is counted per email (3 an hour) and per IP (10 an hour; IPv6 by /64)
with an atomic conditional `UpdateItem` on a fixed hourly window. Counter items expire
through TTL. The email key is a hash, so that table holds no addresses. Over the limit,
the response is the same "check your email" page as for success, so the endpoint reveals
nothing about which addresses are in use. The API stage also throttles overall (5 requests
a second, burst 10) as a cost ceiling. Together these bound SES sending and protect the
account's sending reputation.

## 19. One reproducible package, two functions with separate roles

Both functions ship the same zip but get different handlers, environment variables and IAM
roles. The request function can store codes, count requests and send from
`signin@henryashton.dev` only; the verify function can count guesses and delete codes, update the visitor
log and read the signing key. `lambdas/build.py` installs hash-locked arm64 wheels and
writes a zip with fixed timestamps, permissions and ordering, dropping per-install
installer metadata. It installs with uv, pinned to the same version in CI. A CI build and a local build hash identically, so `plan` only shows a function
change when the code or its dependencies change.

## 20. SES: domain identity with DKIM and a custom MAIL FROM domain

Mail is sent from `signin@henryashton.dev` through a domain identity with 2048-bit Easy
DKIM, which satisfies the zone's strict DMARC policy. The MAIL FROM domain
`mail.henryashton.dev` aligns SPF too and receives bounces, since the apex has a null MX.
Bounces and complaints go to the SES account-level suppression list. New SES accounts are
sandboxed (they can only send to verified addresses), so production access is requested
before launch; `ses_test_recipients` verifies addresses for testing until then.

## 21. Sign in with a six-digit code, not a link

The emailed link (#15) worked, but had two problems for this audience. A recruiter may
find the site at a desk and read the email on a phone; a link signs in whichever device
opens it. And a secret in a URL ends up in browser history, synced tabs and chat previews.
A code can be read on one device and typed on another, and nothing can prefetch it, so the
confirmation page and the GET route went away.

A code is guessable, so the limits carry the security, not the length. Each code allows 5
attempts and expires after 10 minutes, and an address can get 3 codes an hour, so an
attacker gets about 15 guesses an hour at a one-in-a-million code. Six digits is the
length people can carry between devices and that phones offer as autofill. Verification
counts the attempt (a conditional `UpdateItem`: not expired, under the limit) before
comparing the hash, so concurrent guesses can't exceed the limit, then deletes the code
conditionally on its hash so it works once. The table is keyed by email, so requesting a
new code replaces the old one. Wrong, expired, used and never-issued codes get the same
response, which reveals nothing about recent requests for an address.

The stored hash includes the email address. It keeps codes unreadable at a glance, but a
six-digit code's hash can be reversed by brute force, so it isn't a defence against someone
who can read the table; that would need account access, and codes expire in minutes.
The address reaches the code page in the URL fragment, which browsers never send to the
server.

## 22. The API behaviour forwards cookies, though the API ignores them

With cookie forwarding set to none, CloudFront also removes `Set-Cookie` headers from
origin responses, so the signed cookies from the verify function never reached the
browser: sign-in succeeded but `/roles/` still returned 403. Least privilege pointed the
wrong way here. The `/api/*` origin request policy now forwards all cookies. That shares
nothing: the signed cookies are scoped to `Path=/roles/`, so browsers don't send them to
`/api/*`, and the API isn't cached, so there is no cache-key cost.

## 23. The random face: a CloudFront Function, with the pool size read from the bucket

`/img/henry-ashton.jpg` has its own behaviour, whose viewer-request function rewrites the
path to a random `faces/NNN.jpg` before CloudFront looks anything up. That behaviour uses
the managed caching-disabled policy, so each request reaches S3 and gets a fresh pick, and
a response headers policy adds `Cache-Control: no-store` so browsers don't keep it either.
Lambda@Edge isn't an option (#8), and a function is free at this traffic.

A function can't list S3 or read files, so it has to know the pool size. Rather than a
variable that could drift from what was uploaded, Terraform reads the `faces/` keys from
the bucket and writes the count into the function code. A precondition requires the keys
to be exactly `faces/000.jpg` onward with no gaps, so the function can pick a number
rather than carry a list of names. `scripts/upload-faces.sh` renumbers and uploads a pool;
an apply then publishes the new count. The trade-off is that a plan depends on bucket
contents as well as code, which is visible in the plan as a function change. With no faces
uploaded, the function serves a neutral placeholder image instead.

The faces live in the site bucket under `faces/`. The site deploy workflow excludes that
prefix and its role is denied writes to it, so a page deploy can't delete the pool.

## 24. The link-preview image is never a face

LinkedIn shows `og:image` in link previews with no caption, so a generated face there
would look like a photo of Henry. The preview image is the initials and name instead,
drawn by `scripts/make-og-image.py` so it can be regenerated rather than edited by hand.
On the page, the face has `alt="Henry Ashton"` and a visible caption saying it is
generated, linked by `aria-describedby` so screen readers announce it too.

## 25. Faces from FLUX.1 [dev] with XLabs' realism LoRA, on Replicate

The brief asked for GAN faces. The standard choice, NVIDIA's StyleGAN2/3 trained on FFHQ,
is licensed for "research or evaluation purposes only", and FFHQ itself is Flickr photos
of real people under a non-commercial licence. A career site is neither research nor
evaluation, so that licence would be hard to defend.

FLUX.1 [schnell] (Apache 2.0) was tried first, but its faces looked airbrushed. The faces
now come from FLUX.1 [dev] with XLabs' realism LoRA (`xlabs-ai/flux-dev-realism`, pinned
to one version). The [dev] weights are non-commercial, but Replicate states that "if you
generate images on Replicate with FLUX.1 models and their fine-tunes, then you can use
the images commercially"; generating anywhere else would not be covered. A community
"faces" LoRA looked good too, but pulled most faces towards one ethnicity whatever the
prompt said, which suggests a small training set of real people and a risk of outputs
resembling them. XLabs' LoRA is a general photographic style and showed no such pull.
Its training data isn't published either, so every face is reviewed by hand before
upload.

The faces are stand-ins matching Henry's broad profile, young white men, so a visitor who
misses the caption isn't left with a wrong impression of him; the caption says plainly
that it isn't him. Half are portraits and half are candid speaking shots. Each prompt is
built from lists of heritage, age, hair, face shape, build, clothing and setting, picked
by a generator seeded from the face's number (hashed, as consecutive integer seeds gave
neighbouring faces the same traits), so the pool is varied and a resumed run asks for the
same faces. Prompts never name a real person. Name badges were tried and dropped: the
model garbles text, and a badge would make each image claim to be Henry wherever it was
shared without its caption.

Generation runs once from `scripts/generate-faces.py`, one image at a time: about 16
seconds each on Replicate's GPUs, at 1024 px, downscaled to 512. Nothing about it touches
the AWS account. A manifest records the model version, prompt and seed of every face.
