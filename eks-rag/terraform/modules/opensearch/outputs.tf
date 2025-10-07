output "collection_id" {
  description = "OpenSearch Serverless collection ID"
  value       = aws_opensearchserverless_collection.main.id
}

output "collection_arn" {
  description = "OpenSearch Serverless collection ARN"
  value       = aws_opensearchserverless_collection.main.arn
}

output "collection_endpoint" {
  description = "OpenSearch Serverless collection endpoint (without https://)"
  value       = replace(aws_opensearchserverless_collection.main.collection_endpoint, "https://", "")
}

output "collection_name" {
  description = "OpenSearch Serverless collection name"
  value       = aws_opensearchserverless_collection.main.name
}

output "data_access_policy_id" {
  description = "Data access policy ID for dependency tracking"
  value       = aws_opensearchserverless_access_policy.data_access.id
}
