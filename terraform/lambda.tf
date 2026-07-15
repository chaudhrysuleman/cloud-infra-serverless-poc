# --- Route Table for Private Subnets ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "poc-private-route-table"
  }
}

resource "aws_route_table_association" "private_1" {
  subnet_id      = aws_subnet.private_1.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_2" {
  subnet_id      = aws_subnet.private_2.id
  route_table_id = aws_route_table.private.id
}

# --- VPC Gateway Endpoint for S3 ---
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  tags = {
    Name = "poc-s3-endpoint"
  }
}

# --- VPC Interface Endpoint for SQS ---
resource "aws_vpc_endpoint" "sqs" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sqs"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "poc-sqs-endpoint"
  }
}

# --- VPC Interface Endpoint for SNS ---
resource "aws_vpc_endpoint" "sns" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.${var.aws_region}.sns"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = [aws_subnet.private_1.id, aws_subnet.private_2.id]
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true

  tags = {
    Name = "poc-sns-endpoint"
  }
}

# --- S3 Object for Lambda deployment package ---
resource "aws_s3_object" "lambda_jar" {
  bucket = aws_s3_bucket.invoices.id
  key    = "cloud-infra-poc-lambda.jar"
  source = "${path.module}/../app/target/cloud-infra-poc-0.0.1-SNAPSHOT.jar"
  etag   = filemd5("${path.module}/../app/target/cloud-infra-poc-0.0.1-SNAPSHOT.jar")
}

# --- AWS Lambda Function: API (REST endpoints) ---
resource "aws_lambda_function" "api" {
  s3_bucket        = aws_s3_bucket.invoices.id
  s3_key           = aws_s3_object.lambda_jar.key
  source_code_hash = aws_s3_object.lambda_jar.etag
  function_name    = "poc-api-lambda"
  role          = aws_iam_role.lambda.arn
  handler       = "com.suleman.poc.StreamLambdaHandler::handleRequest"
  runtime       = "java17"
  timeout       = 30
  memory_size   = 1024
  publish       = true

  snap_start {
    apply_on = "PublishedVersions"
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST       = split(":", aws_db_instance.postgres.endpoint)[0]
      DB_PORT       = "5432"
      DB_NAME       = var.db_name
      DB_USER       = var.db_username
      DB_PASSWORD   = var.db_password
      SNS_TOPIC_ARN = aws_sns_topic.order_placed.arn
      S3_BUCKET     = aws_s3_bucket.invoices.id
    }
  }

  depends_on = [
    aws_db_instance.postgres,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.sqs,
    aws_vpc_endpoint.sns
  ]
}

# --- AWS Lambda Function: SQS Consumers ---
resource "aws_lambda_function" "sqs" {
  s3_bucket        = aws_s3_bucket.invoices.id
  s3_key           = aws_s3_object.lambda_jar.key
  source_code_hash = aws_s3_object.lambda_jar.etag
  function_name    = "poc-sqs-lambda"
  role          = aws_iam_role.lambda.arn
  handler       = "com.suleman.poc.SqsLambdaHandler::handleRequest"
  runtime       = "java17"
  timeout       = 30
  memory_size   = 1024
  publish       = true

  snap_start {
    apply_on = "PublishedVersions"
  }

  vpc_config {
    subnet_ids         = [aws_subnet.private_1.id, aws_subnet.private_2.id]
    security_group_ids = [aws_security_group.lambda.id]
  }

  environment {
    variables = {
      DB_HOST       = split(":", aws_db_instance.postgres.endpoint)[0]
      DB_PORT       = "5432"
      DB_NAME       = var.db_name
      DB_USER       = var.db_username
      DB_PASSWORD   = var.db_password
      SNS_TOPIC_ARN = aws_sns_topic.order_placed.arn
      S3_BUCKET     = aws_s3_bucket.invoices.id
    }
  }

  depends_on = [
    aws_db_instance.postgres,
    aws_vpc_endpoint.s3,
    aws_vpc_endpoint.sqs,
    aws_vpc_endpoint.sns
  ]
}

# --- SQS Trigger Mappings ---
resource "aws_lambda_event_source_mapping" "notification" {
  event_source_arn = aws_sqs_queue.notification.arn
  function_name    = aws_lambda_function.sqs.arn
}

resource "aws_lambda_event_source_mapping" "invoice" {
  event_source_arn = aws_sqs_queue.invoice.arn
  function_name    = aws_lambda_function.sqs.arn
}

resource "aws_lambda_event_source_mapping" "delivery" {
  event_source_arn = aws_sqs_queue.delivery.arn
  function_name    = aws_lambda_function.sqs.arn
}

# --- API Gateway HTTP API (Serverless Entry Point) ---
resource "aws_apigatewayv2_api" "lambda" {
  name          = "poc-api-gateway"
  protocol_type = "HTTP"
}

# --- API Gateway Stage ---
resource "aws_apigatewayv2_stage" "lambda" {
  api_id      = aws_apigatewayv2_api.lambda.id
  name        = "$default"
  auto_deploy = true
}

# --- API Gateway Integration with Lambda ---
resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.lambda.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.api.qualified_invoke_arn
  payload_format_version = "1.0"
}

# --- API Gateway Routes ---
resource "aws_apigatewayv2_route" "any" {
  api_id    = aws_apigatewayv2_api.lambda.id
  route_key = "ANY /{proxy+}"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_route" "root" {
  api_id    = aws_apigatewayv2_api.lambda.id
  route_key = "ANY /"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

# --- API Gateway Permissions for Lambda ---
resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowExecutionFromAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}

resource "aws_lambda_permission" "apigw_qualified" {
  statement_id  = "AllowExecutionFromAPIGatewayQualified"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.api.qualified_arn
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.lambda.execution_arn}/*/*"
}
