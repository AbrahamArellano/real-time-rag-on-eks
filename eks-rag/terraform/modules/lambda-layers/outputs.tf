output "aws4auth_layer_arn" {
  description = "ARN of the AWS4Auth Lambda layer"
  value       = aws_lambda_layer_version.aws4auth.arn
}

output "opensearch_layer_arn" {
  description = "ARN of the OpenSearch Python Lambda layer"
  value       = aws_lambda_layer_version.opensearch.arn
}
