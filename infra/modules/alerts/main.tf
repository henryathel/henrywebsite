# Emails to Henry: one when someone signs in for the first time, and budget alerts.

data "aws_caller_identity" "current" {}

# --- New visitors: visitor log stream -> EventBridge Pipe -> SNS -> email -------------
#
# No Lambda: the pipe filters the stream to new items (first sign-ins) and formats the
# message itself, so there is no code to maintain and nothing on the sign-in path.

# The AWS-managed key: the pipe publishes as an IAM role in this account, which that
# key's policy allows. (Service principals such as Budgets couldn't use it; see below.)
resource "aws_sns_topic" "visitors" {
  name              = "${var.project}-new-visitors"
  kms_master_key_id = "alias/aws/sns"
}

# SNS emails a confirmation link first; nothing is delivered until it is clicked.
resource "aws_sns_topic_subscription" "visitors_email" {
  topic_arn = aws_sns_topic.visitors.arn
  protocol  = "email"
  endpoint  = var.notification_email
}

data "aws_iam_policy_document" "pipe_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["pipes.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

data "aws_iam_policy_document" "pipe" {
  statement {
    sid = "ReadVisitorStream"
    actions = [
      "dynamodb:DescribeStream",
      "dynamodb:GetRecords",
      "dynamodb:GetShardIterator",
    ]
    resources = [var.visitors_stream_arn]
  }

  # ListStreams has no resource type in the IAM reference; it returns stream ARNs only.
  statement {
    sid       = "ListStreams"
    actions   = ["dynamodb:ListStreams"]
    resources = ["*"]
  }

  statement {
    sid       = "Notify"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.visitors.arn]
  }
}

resource "aws_iam_role" "pipe" {
  name               = "${var.project}-new-visitor-pipe"
  description        = "Assumed by the pipe that emails Henry about first sign-ins."
  assume_role_policy = data.aws_iam_policy_document.pipe_trust.json
}

resource "aws_iam_role_policy" "pipe" {
  name   = "${var.project}-new-visitor-pipe"
  role   = aws_iam_role.pipe.id
  policy = data.aws_iam_policy_document.pipe.json
}

resource "aws_pipes_pipe" "new_visitor" {
  name        = "${var.project}-new-visitor"
  description = "Email Henry when someone signs in for the first time"
  role_arn    = aws_iam_role.pipe.arn
  source      = var.visitors_stream_arn
  target      = aws_sns_topic.visitors.arn

  source_parameters {
    dynamodb_stream_parameters {
      starting_position = "LATEST"
      batch_size        = 1
      # The default retries forever, which would hold up later records for a day.
      maximum_retry_attempts = 10
    }

    # A first sign-in creates the item; later sign-ins only modify it.
    filter_criteria {
      filter {
        pattern = jsonencode({ eventName = ["INSERT"] })
      }
    }
  }

  target_parameters {
    input_template = "New visitor on ${var.domain_name}: <$.dynamodb.NewImage.email.S> signed in for the first time at <$.dynamodb.NewImage.first_seen.S>."
  }

  depends_on = [aws_iam_role_policy.pipe]
}

# --- Budget ---------------------------------------------------------------------------
#
# Budgets emails the address directly. Routing it through the topic would need a
# customer-managed KMS key ($1/month), as the Budgets service can't use the AWS-managed one.

resource "aws_budgets_budget" "monthly" {
  name         = "${var.project}-monthly"
  budget_type  = "COST"
  limit_amount = format("%.2f", var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.notification_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.notification_email]
  }
}
