variable "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  type        = string
}

variable "opensearch_endpoint" {
  description = "OpenSearch Serverless collection endpoint (without https://)"
  type        = string
}

variable "opensearch_collection_arn" {
  description = "ARN of the OpenSearch Serverless collection"
  type        = string
}

variable "index_name" {
  description = "OpenSearch index name"
  type        = string
  default     = "error-logs-mock"
}

variable "aws4auth_layer_arn" {
  description = "ARN of the AWS4Auth Lambda layer"
  type        = string
}

variable "opensearch_layer_arn" {
  description = "ARN of the OpenSearch Python Lambda layer"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}
