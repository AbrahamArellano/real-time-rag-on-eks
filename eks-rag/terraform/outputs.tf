output "service_account_role_arn" {
  description = "IAM role ARN for the Kubernetes service account"
  value       = module.iam.role_arn
}

output "opensearch_collection_endpoint" {
  description = "OpenSearch Serverless collection endpoint"
  value       = module.opensearch.collection_endpoint
}

output "opensearch_collection_id" {
  description = "OpenSearch Serverless collection ID"
  value       = module.opensearch.collection_id
}

output "opensearch_collection_arn" {
  description = "OpenSearch Serverless collection ARN"
  value       = module.opensearch.collection_arn
}

output "ecr_repository_url" {
  description = "ECR repository URL for the RAG service"
  value       = module.ecr.repository_url
}

output "rag_service_endpoint" {
  description = "Internal ClusterIP endpoint for the RAG service (accessed by UI)"
  value       = module.kubernetes.service_endpoint
}

output "kubectl_test_command" {
  description = "Command to test the RAG service from within cluster"
  value       = <<-EOT
    # Test from inside a pod:
    kubectl run test-pod --rm -it --image=curlimages/curl --restart=Never -- \
      curl -X POST http://${module.kubernetes.service_endpoint}/submit_query \
      -H "Content-Type: application/json" \
      -d '{"query": "Show critical engine temperature alerts"}'
  EOT
}

output "ui_ecr_repository_url" {
  description = "ECR repository URL for the Gradio UI"
  value       = module.ecr_ui.repository_url
}

output "ui_alb_hostname" {
  description = "ALB hostname for accessing the Gradio UI (internet-facing)"
  value       = module.ui.alb_hostname
}

output "ui_url" {
  description = "Full URL to access the Gradio UI"
  value       = "http://${module.ui.alb_hostname}"
}

output "kinesis_stream_arn" {
  description = "ARN of the Kinesis Data Stream"
  value       = module.kinesis.stream_arn
}

output "kinesis_stream_name" {
  description = "Name of the Kinesis Data Stream"
  value       = module.kinesis.stream_name
}

output "opensearch_index_name" {
  description = "Name of the OpenSearch index"
  value       = module.opensearch_index.index_name
}

output "lambda_producer_name" {
  description = "Name of the Lambda producer function"
  value       = module.lambda_producer.lambda_function_name
}

output "lambda_consumer_name" {
  description = "Name of the Lambda consumer function"
  value       = module.lambda_consumer.lambda_function_name
}

output "aws_region" {
  description = "AWS region where resources are deployed"
  value       = var.aws_region
}

output "deployment_status" {
  description = "Deployment summary"
  value = {
    cluster_name          = var.cluster_name
    namespace             = var.namespace
    service_account       = var.service_account_name
    opensearch_collection = var.collection_name
    opensearch_index      = module.opensearch_index.index_name
    vllm_service          = "${var.vllm_service_name}.${var.vllm_namespace}.svc.cluster.local"
    rag_service_internal  = module.kubernetes.service_endpoint
    ui_public_url         = "http://${module.ui.alb_hostname}"
    kinesis_stream        = module.kinesis.stream_name
    lambda_producer       = module.lambda_producer.lambda_function_name
    lambda_consumer       = module.lambda_consumer.lambda_function_name
    data_pipeline_status  = "Logs generated every minute → Kinesis → Lambda → Bedrock → OpenSearch"
  }
}
