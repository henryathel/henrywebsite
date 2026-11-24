output "api_domain" {
  description = "execute-api hostname, used as the CloudFront origin for /api/*."
  value       = replace(aws_apigatewayv2_api.auth.api_endpoint, "https://", "")
}

output "origin_secret" {
  description = "Header value CloudFront sends to the API so the functions can reject direct calls."
  value       = random_password.origin_secret.result
  sensitive   = true
}

output "key_group_id" {
  description = "CloudFront key group trusted for signed cookies on /roles/*."
  value       = aws_cloudfront_key_group.roles.id
}

output "visitors_stream_arn" {
  description = "Stream of changes to the visitor log; a new item is a first sign-in."
  value       = aws_dynamodb_table.visitors.stream_arn
}
