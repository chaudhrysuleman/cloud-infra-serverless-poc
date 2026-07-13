# --- SNS Topic ---
resource "aws_sns_topic" "order_placed" {
  name = "order-placed-topic"
}

# --- SQS Queues ---
resource "aws_sqs_queue" "notification" {
  name                      = "notification-queue"
  message_retention_seconds = 86400 # 1 day
}

resource "aws_sqs_queue" "invoice" {
  name                      = "invoice-queue"
  message_retention_seconds = 86400
}

resource "aws_sqs_queue" "delivery" {
  name                      = "delivery-queue"
  message_retention_seconds = 86400
}

# --- SQS Subscriptions to SNS ---
resource "aws_sns_topic_subscription" "notification" {
  topic_arn = aws_sns_topic.order_placed.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.notification.arn
}

resource "aws_sns_topic_subscription" "invoice" {
  topic_arn = aws_sns_topic.order_placed.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.invoice.arn
}

resource "aws_sns_topic_subscription" "delivery" {
  topic_arn = aws_sns_topic.order_placed.arn
  protocol  = "sqs"
  endpoint  = aws_sqs_queue.delivery.arn
}

# --- SQS Policy Helper (Allows SNS Topic to send messages to SQS) ---
data "aws_iam_policy_document" "sqs_sns_policy" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.amazonaws.com"]
    }
    actions   = ["sqs:SendMessage"]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_sns_topic.order_placed.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "notification" {
  queue_url = aws_sqs_queue.notification.id
  policy    = data.aws_iam_policy_document.sqs_sns_policy.json
}

resource "aws_sqs_queue_policy" "invoice" {
  queue_url = aws_sqs_queue.invoice.id
  policy    = data.aws_iam_policy_document.sqs_sns_policy.json
}

resource "aws_sqs_queue_policy" "delivery" {
  queue_url = aws_sqs_queue.delivery.id
  policy    = data.aws_iam_policy_document.sqs_sns_policy.json
}
