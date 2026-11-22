# Two private buckets, readable only by this distribution through Origin Access Control:
#   site:  public pages, deployed from this repo.
#   roles: the protected write-ups, deployed from the private content repo. It is the
#          origin only for the /roles/* behaviour, which requires signed cookies, so no
#          other path through CloudFront can reach its objects.
locals {
  buckets = {
    site  = "${var.project}-site-${data.aws_caller_identity.current.account_id}"
    roles = "${var.project}-roles-${data.aws_caller_identity.current.account_id}"
  }
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "this" {
  #checkov:skip=CKV_AWS_18:Access logging would need another bucket; not worth it for static content.
  #checkov:skip=CKV_AWS_144:Cross-region replication is not worth the cost; content is rebuilt from git.
  #checkov:skip=CKV_AWS_145:SSE-S3 instead of a KMS CMK: OAC reads would need key grants and the key costs monthly.
  #checkov:skip=CKV2_AWS_62:No consumer for bucket event notifications.
  for_each = local.buckets

  bucket = each.value
}

resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning gives a rollback path for a bad deploy or an accidental --delete.
resource "aws_s3_bucket_versioning" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  for_each = aws_s3_bucket.this

  # s3:ListBucket makes a missing object a 404 rather than a 403, so 403 is reserved
  # for CloudFront's signed-cookie check on /roles/*.
  statement {
    sid       = "CloudFrontRead"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [each.value.arn, "${each.value.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [each.value.arn, "${each.value.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each = aws_s3_bucket.this

  bucket = each.value.id
  policy = data.aws_iam_policy_document.bucket[each.key].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# The site bucket's resources were singular before the roles bucket was added.
moved {
  from = aws_s3_bucket.site
  to   = aws_s3_bucket.this["site"]
}

moved {
  from = aws_s3_bucket_ownership_controls.site
  to   = aws_s3_bucket_ownership_controls.this["site"]
}

moved {
  from = aws_s3_bucket_public_access_block.site
  to   = aws_s3_bucket_public_access_block.this["site"]
}

moved {
  from = aws_s3_bucket_versioning.site
  to   = aws_s3_bucket_versioning.this["site"]
}

moved {
  from = aws_s3_bucket_server_side_encryption_configuration.site
  to   = aws_s3_bucket_server_side_encryption_configuration.this["site"]
}

moved {
  from = aws_s3_bucket_lifecycle_configuration.site
  to   = aws_s3_bucket_lifecycle_configuration.this["site"]
}

moved {
  from = aws_s3_bucket_policy.site
  to   = aws_s3_bucket_policy.this["site"]
}
