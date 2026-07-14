output "api_gateway_url" {
  value       = aws_apigatewayv2_stage.lambda.invoke_url
  description = "HTTP URL of the API Gateway exposing the Spring Boot Lambda function"
}

output "rds_endpoint" {
  value       = aws_db_instance.postgres.endpoint
  description = "Database endpoint connection string"
}
