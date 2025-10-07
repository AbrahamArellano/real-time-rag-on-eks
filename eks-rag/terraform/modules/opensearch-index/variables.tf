variable "opensearch_endpoint" {
  description = "OpenSearch Serverless collection endpoint (without https://)"
  type        = string
}

variable "index_name" {
  description = "Name of the OpenSearch index to create"
  type        = string
  default     = "error-logs-mock"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "opensearch_collection_id" {
  description = "OpenSearch collection ID for dependency management"
  type        = string
}

variable "data_access_policy_id" {
  description = "ID of the data access policy (for dependency tracking)"
  type        = string
}
