# --- Lambda Security Group ---
resource "aws_security_group" "lambda" {
  name        = "poc-lambda-sg"
  description = "Security group for Lambda functions"
  vpc_id      = aws_vpc.main.id

  # Allow all outbound traffic (so Lambda can connect to RDS, S3, SQS, SNS)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "poc-lambda-sg"
  }
}

# --- RDS Security Group ---
resource "aws_security_group" "rds" {
  name        = "poc-rds-sg"
  description = "Allow PostgreSQL database access from Lambda functions"
  vpc_id      = aws_vpc.main.id

  # Allow PostgreSQL traffic from the Lambda security group ONLY
  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "poc-rds-sg"
  }
}

# --- VPC Endpoints Security Group ---
resource "aws_security_group" "vpc_endpoints" {
  name        = "poc-vpc-endpoints-sg"
  description = "Security group for VPC Endpoints"
  vpc_id      = aws_vpc.main.id

  # Allow HTTPS traffic from Lambda functions inside the VPC
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [aws_security_group.lambda.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "poc-vpc-endpoints-sg"
  }
}
