variable "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  type        = string
}

variable "schedule_expression" {
  description = "EventBridge schedule expression (e.g., 'rate(1 minute)')"
  type        = string
  default     = "rate(1 minute)"
}

variable "logs_per_invocation" {
  description = "Number of logs to generate per Lambda invocation"
  type        = number
  default     = 10
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}
