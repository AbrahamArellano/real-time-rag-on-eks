output "lambda_function_arn" {
  description = "ARN of the Lambda consumer function"
  value       = aws_lambda_function.consumer.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda consumer function"
  value       = aws_lambda_function.consumer.function_name
}

output "lambda_role_arn" {
  description = "ARN of the Lambda consumer IAM role"
  value       = aws_iam_role.consumer.arn
}

output "event_source_mapping_id" {
  description = "ID of the Kinesis event source mapping"
  value       = aws_lambda_event_source_mapping.kinesis_trigger.id
}
