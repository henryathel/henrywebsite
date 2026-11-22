#!/usr/bin/env bash
# Creates the RSA key pair for CloudFront signed cookies.
#
# The private key goes straight into SSM Parameter Store as a SecureString and is then
# deleted locally, so it never touches the repo, Terraform state or the Lambda
# environment. The public key is written to infra/keys/ to be committed; Terraform
# registers it with CloudFront.
#
# Usage: AWS_PROFILE=henrywebsite scripts/create-signing-key.sh [--rotate]
#
# --rotate replaces an existing key. Visitors' current cookies stop working once the new
# public key is applied, so they sign in again. Run `terraform apply` straight after.
set -euo pipefail

PARAMETER=/henrywebsite/cookie-signing-key
REGION=eu-north-1
EXPECTED_ACCOUNT=904527474147
PUBLIC_KEY="$(cd "$(dirname "$0")/.." && pwd)/infra/keys/cookie-signing-public.pem"

rotate=false
[[ "${1:-}" == "--rotate" ]] && rotate=true

account=$(aws sts get-caller-identity --query Account --output text)
if [[ "$account" != "$EXPECTED_ACCOUNT" ]]; then
  echo "Refusing: credentials are for account $account, not $EXPECTED_ACCOUNT." >&2
  exit 1
fi

if [[ -e "$PUBLIC_KEY" && "$rotate" != true ]]; then
  echo "A key already exists ($PUBLIC_KEY). Use --rotate to replace it." >&2
  exit 1
fi

umask 077
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$workdir/private.pem" 2>/dev/null

overwrite=()
[[ "$rotate" == true ]] && overwrite=(--overwrite)
aws ssm put-parameter \
  --region "$REGION" \
  --name "$PARAMETER" \
  --type SecureString \
  --description "CloudFront cookie-signing private key (scripts/create-signing-key.sh)" \
  --value "file://$workdir/private.pem" \
  "${overwrite[@]}" >/dev/null

umask 022
openssl pkey -in "$workdir/private.pem" -pubout -out "$PUBLIC_KEY"

echo "Private key stored in SSM as $PARAMETER (SecureString); local copy deleted."
echo "Public key written to ${PUBLIC_KEY#"$PWD/"}. Commit it, then run terraform apply."
