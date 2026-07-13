# --- Trust Policy for EC2 Service ---
data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

# --- IAM Role for EC2 Instance ---
resource "aws_iam_role" "ec2" {
  name               = "poc-ec2-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
}

# --- Inline Policies for S3, SNS, SQS permissions ---
data "aws_iam_policy_document" "ec2_permissions" {
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

resource "aws_iam_role_policy" "ec2" {
  name   = "poc-ec2-policy"
  role   = aws_iam_role.ec2.id
  policy = data.aws_iam_policy_document.ec2_permissions.json
}

# --- IAM Instance Profile for EC2 ---
resource "aws_iam_instance_profile" "ec2" {
  name = "poc-ec2-instance-profile"
  role = aws_iam_role.ec2.name
}
