#!/usr/bin/env bash
# Upload a pool of generated faces to the site bucket as faces/000.jpg, faces/001.jpg, ...
#
# Usage: AWS_PROFILE=henrywebsite scripts/upload-faces.sh <dir of .jpg files>
#
# Files are renumbered in name order, so their original names don't matter. Run
# `terraform apply` afterwards: the random-face function reads the pool size from the
# bucket when it is planned (docs/decisions.md #23).
set -euo pipefail

src=${1:?usage: $0 <dir of .jpg files>}
account=904527474147

actual=$(aws sts get-caller-identity --query Account --output text)
if [[ $actual != "$account" ]]; then
  echo "Signed in to account $actual, expected $account." >&2
  exit 1
fi

bucket=$(terraform -chdir="$(dirname "$0")/../infra" output -raw site_bucket)

mapfile -t files < <(find "$src" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.jpeg' \) | sort)
count=${#files[@]}
if (( count == 0 || count > 1000 )); then
  echo "Found $count JPEGs in $src; need between 1 and 1000." >&2
  exit 1
fi
for f in "${files[@]}"; do
  if [[ $(file -b --mime-type "$f") != image/jpeg ]]; then
    echo "$f is not a JPEG." >&2
    exit 1
  fi
done

staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
for i in "${!files[@]}"; do
  cp "${files[$i]}" "$staging/$(printf '%03d' "$i").jpg"
done

# Anything else under faces/ would fail the Terraform precondition. If the pool shrinks,
# the live function may pick a deleted face until the apply, so apply straight away.
stale=$(aws s3api list-objects-v2 --bucket "$bucket" --prefix faces/ \
  --query 'Contents[].Key' --output text | tr '\t' '\n' \
  | awk -v n="$count" '$0 != "None" && !($0 ~ /^faces\/[0-9][0-9][0-9]\.jpg$/ && substr($0, 7, 3) + 0 < n)')
if [[ -n $stale ]]; then
  echo "These keys are outside the new pool and will be deleted:"
  echo "$stale"
  read -r -p "Continue? [y/N] " answer
  [[ $answer == [yY] ]] || exit 1
fi

echo "Uploading $count faces to s3://$bucket/faces/"
aws s3 cp "$staging/" "s3://$bucket/faces/" --recursive --content-type image/jpeg --only-show-errors

if [[ -n $stale ]]; then
  while read -r key; do
    aws s3api delete-object --bucket "$bucket" --key "$key" >/dev/null
  done <<< "$stale"
fi

echo "Done. Now run: cd infra && terraform apply"
