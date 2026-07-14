# --- Trust Policy for Lambda Service ---
data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

# --- IAM Role for Lambda Functions ---
resource "aws_iam_role" "lambda" {
  name               = "poc-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

# --- Attach AWSLambdaVPCAccessExecutionRole Managed Policy ---
# This permits Lambda functions running inside a VPC to manage Network Interfaces (create, delete, list).
resource "aws_iam_role_policy_attachment" "lambda_vpc" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

# --- Inline Policies for S3, SNS, SQS permissions ---
data "aws_iam_policy_document" "lambda_permissions" {
  # S3 Permission (Read/Write to invoices bucket)
  statement {
    effect    = "Allow"
    actions   = ["s3:*"]
    resources = [
      aws_s3_bucket.invoices.arn,
      "${aws_s3_bucket.invoices.arn}/*"
    ]
  }

  # SNS Permission (Publishing events)
  statement {
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.order_placed.arn]
  }

  # SQS Permission (Polling and deleting events)
  statement {
    effect    = "Allow"
    actions   = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:GetQueueUrl"
    ]
    resources = [
      aws_sqs_queue.notification.arn,
      aws_sqs_queue.invoice.arn,
      aws_sqs_queue.delivery.arn
    ]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "poc-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}
