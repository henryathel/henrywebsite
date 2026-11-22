# Personal career site — project brief

A personal career site for Henry Ashton, linked from LinkedIn. It is also a portfolio piece:
it should demonstrate clean, production-quality AWS serverless engineering. Every choice
should be one Henry can explain and defend in an interview.

## What the site does

- **Public landing page** (`/`): a single-page summary of career, headline results, research and
  education. This is what LinkedIn links to. It must persuade on its own.
- **Protected role pages** (`/roles/*`): detailed write-ups of each role and project. Visitors get
  access by entering their email address and then a six-digit code emailed to it.
- **Generated face** on the landing page: a face produced by a GAN, different on each load,
  visibly labelled as *not* a photo of Henry (see "Face image" below).
- **Visitor log**: every successful sign-in is recorded (email, time) so Henry can see who looked.

Page content (HTML/Markdown) will arrive later in `site/`. Until then, use simple placeholder
pages: `index.html`, `login.html`, `roles/index.html`, `roles/example.html`.

## Architecture

Region: `eu-north-1` (Stockholm), except resources CloudFront requires in `us-east-1` (ACM cert).

The site has its own AWS account in Henry's organization. An org-wide SCP fully allows only
`eu-north-1`; in `us-east-1` it allows only global services (CloudFront, IAM, ACM, Route 53,
Budgets, KMS, STS, Logs, WAF) and denies regional ones (Lambda, DynamoDB, SES, S3 buckets,
SNS). Every other region is denied. Design within this; don't plan on changing the SCP.

- **Static site**: private S3 bucket, served only through CloudFront with Origin Access Control.
- **CloudFront behaviours**:
  - `/` and `/assets/*`, `/login*`: public.
  - `/roles/*`: restricted with a **trusted key group**, so requests need valid CloudFront
    **signed cookies**. Unauthenticated requests get 403; map 403 to `/login.html` via a
    custom error response. Role pages are in their **own private bucket**, the origin only
    for this behaviour (`docs/decisions.md` #14).
  - `/api/*`: routed to API Gateway.
  - `/img/henry-ashton.jpg`: the face image (see below). Must not be cached.
- **Auth API**: API Gateway HTTP API + Python Lambdas.
  - Sign-in is by **six-digit code**, not link (`docs/decisions.md` #21).
  - `POST /api/auth/request` `{email}`: validate the email, rate-limit (per email and per IP),
    generate a random six-digit code, store **only its hash** in DynamoDB keyed by email
    (replacing any earlier code) with a 10-minute expiry, and send it with SES. Always
    return the same response, whether or not the email is new or rate-limited, so the
    endpoint can't be used to probe for addresses.
  - `POST /api/auth/verify` `{email, code}`: count the attempt atomically (at most 5 per
    code, not expired), compare the hash, then **conditionally delete** the code so it works
    once. On success, write to the visitor log, issue CloudFront signed cookies (valid 5
    days) and redirect to `/roles/`. Wrong, expired, used and never-issued codes all get the
    same response.
- **Signing key** for the cookies: generate the key pair outside Terraform state if possible;
  store the private key in SSM Parameter Store (SecureString) or Secrets Manager; the public
  key goes in the CloudFront key group.
- **DynamoDB**: `sign-in-codes` table (hash key = email, TTL attribute), `rate-limits` table
  (hashed keys, TTL) and `visitors` table (email, timestamps). On-demand billing.
- **SES**: verify the domain with DKIM. Note: new SES accounts are in the **sandbox** and can
  only send to verified addresses. Request production access before going live.
- **Notification** (optional): SNS email to Henry on each new visitor.

## Face image

- A pool of a few hundred pre-generated GAN faces stored in S3 under `faces/` (generated
  separately on a GPU machine; not part of this repository's build). Use numbered filenames.
- `/img/henry-ashton.jpg` serves a **random** face from the pool on each request, using a
  CloudFront Function that rewrites the URI to a random `faces/NNN.jpg`. **Lambda@Edge is not
  an option**: it must be created in `us-east-1`, where the SCP denies Lambda. Use a
  cache policy with caching disabled for this path, and `Cache-Control: no-store`.
- Markup on the landing page: `alt="Henry Ashton"`, a visible caption stating the face is
  GAN-generated and is not a photo of Henry, linked with `aria-describedby` so screen-reader
  users get the caption too.
- **`og:image` must NOT be a face.** LinkedIn shows it in link previews with no caption. Use a
  neutral image (initials or an abstract graphic).

## Privacy and content rules

- The current employer (Athelas Data) is **never named on public pages**, including titles,
  metadata and structured data. It may appear on `/roles/*` only.
- `/roles/*` and `/login*` send `X-Robots-Tag: noindex` (CloudFront response headers policy).
- No client names, datasets or internal system details from any employer.

## Engineering conventions

- **Everything in Terraform.** No manual console changes. Remote state in S3 with locking.
  Split into modules: `site`, `auth`, `faces`, `ci`.
- **Lambdas**: Python 3.12, type-hinted, Pydantic for request validation, structured logging,
  least-privilege IAM role per function. Tests with pytest (use moto for AWS calls).
- **CI/CD**: GitHub Actions authenticating to AWS with **OIDC** (no stored keys).
  - On pull request: `terraform fmt -check`, `validate`, `plan` (read-only role), checkov,
    ruff, mypy and pytest.
  - On merge to `main`: sync `site/` to S3 (excluding `roles/*` and `faces/*`), invalidate
    CloudFront.
  - **CI never runs `terraform apply`.** Henry applies locally. No CI role may modify
    infrastructure.
- **Repositories**: this repo (`henryathel/henrywebsite`) is **public**. Real `/roles/*`
  content lives in the private `henryathel/henrywebsite-content` repo, deployed by its own
  workflow with an OIDC role limited to the `roles/` prefix. Never commit real role
  write-ups here; only placeholders.
- Least privilege throughout: the OIDC role, each Lambda role and the S3 bucket policy should
  grant only what is needed.
- AWS Budgets alarm at a small monthly threshold. Aim for free-tier-level costs.
- Keep a short `docs/decisions.md` recording each significant choice and why.

## Suggested order

1. Terraform backend, OIDC role for GitHub, CI workflow skeleton.
2. S3 + CloudFront + placeholder pages + custom domain and certificate.
3. Auth: DynamoDB, Lambdas, API Gateway, SES, signed cookies, protected `/roles/*`.
4. Face pool bucket path and the random-face CloudFront Function.
5. Visitor log notifications, budget alarm, `noindex` headers, docs.

## Open questions for Henry

_Settled: domain `henryashton.dev` (registered at Namecheap, DNS in Route 53), canonical host
`www.henryashton.dev` with the apex redirecting to it. Cookie lifetime 5 days; sign-in code
expiry 10 minutes, 6 digits, 5 attempts; sender `signin@henryashton.dev`._

- Email address that should receive visitor notifications (step 5).
