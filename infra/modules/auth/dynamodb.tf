# On-demand tables. Each expires items through a TTL attribute; DynamoDB deletes expired
# items only eventually, so code that cares (token expiry) also checks the time itself.

resource "aws_dynamodb_table" "tokens" {
  #checkov:skip=CKV_AWS_28:Tokens live for minutes; there is nothing worth restoring.
  #checkov:skip=CKV_AWS_119:Encrypted with the AWS-owned key; a CMK costs monthly and adds no access control here.
  name         = "${var.project}-tokens"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "token_hash"

  attribute {
    name = "token_hash"
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
