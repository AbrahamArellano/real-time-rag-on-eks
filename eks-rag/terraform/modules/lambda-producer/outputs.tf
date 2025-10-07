output "lambda_function_arn" {
  description = "ARN of the Lambda producer function"
  value       = aws_lambda_function.producer.arn
}

output "lambda_function_name" {
  description = "Name of the Lambda producer function"
  value       = aws_lambda_function.producer.function_name
}

output "eventbridge_rule_arn" {
  description = "ARN of the EventBridge schedule rule"
  value       = aws_cloudwatch_event_rule.producer_schedule.arn
}

output "kinesis_stream_name" {
  description = "Kinesis stream name for vehicle logs"
  value       = var.kinesis_stream_name
}
