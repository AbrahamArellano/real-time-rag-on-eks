output "stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = aws_kinesis_stream.error_logs.arn
}

output "stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = aws_kinesis_stream.error_logs.name
}
