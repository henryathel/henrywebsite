# On-demand tables. Codes and rate-limit counters expire through a TTL attribute; DynamoDB
# deletes expired items only eventually, so the code also checks expiry itself.

# One live code per address: requesting a new code replaces the old one.
resource "aws_dynamodb_table" "codes" {
  #checkov:skip=CKV_AWS_28:Codes live for minutes; there is nothing worth restoring.
  #checkov:skip=CKV_AWS_119:Encrypted with the AWS-owned key; a CMK costs monthly and adds no access control here.
  name         = "${var.project}-sign-in-codes"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "email"

  attribute {
    name = "email"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

resource "aws_dynamodb_table" "rate_limits" {
  #checkov:skip=CKV_AWS_28:Counters live for an hour; there is nothing worth restoring.
  #checkov:skip=CKV_AWS_119:Encrypted with the AWS-owned key; a CMK costs monthly and adds no access control here.
  name         = "${var.project}-rate-limits"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "key"

  attribute {
    name = "key"
    type = "S"
  }

  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
}

# The visitor log is the one table worth recovering, so it has point-in-time recovery.
resource "aws_dynamodb_table" "visitors" {
  #checkov:skip=CKV_AWS_119:Encrypted with the AWS-owned key; a CMK costs monthly and adds no access control here.
  name         = "${var.project}-visitors"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "email"

  attribute {
    name = "email"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }

  deletion_protection_enabled = true
}
