variable "opensearch_collection_endpoint" {
  description = "OpenSearch Serverless collection endpoint"
  type        = string
}

variable "opensearch_collection_name" {
  description = "OpenSearch Serverless collection name"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}

variable "scripts_path" {
  description = "Path to opensearch-setup scripts directory"
  type        = string
}
