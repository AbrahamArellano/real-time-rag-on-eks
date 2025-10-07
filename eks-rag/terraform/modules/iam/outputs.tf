output "role_arn" {
  description = "IAM role ARN for the service account"
  value       = aws_iam_role.eks_rag_sa.arn
}

output "role_name" {
  description = "IAM role name"
  value       = aws_iam_role.eks_rag_sa.name
}

output "bedrock_policy_arn" {
  description = "Bedrock policy ARN"
  value       = aws_iam_policy.bedrock_policy.arn
}

output "opensearch_policy_arn" {
  description = "OpenSearch policy ARN"
  value       = aws_iam_policy.opensearch_policy.arn
}
