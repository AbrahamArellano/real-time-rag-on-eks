output "service_endpoint" {
  description = "Internal ClusterIP endpoint for the RAG service"
  value       = "${kubernetes_service_v1.eks_rag_service.metadata[0].name}.${var.namespace}.svc.cluster.local"
}

output "deployment_name" {
  description = "Deployment name"
  value       = kubernetes_deployment_v1.eks_rag.metadata[0].name
}

output "service_account_name" {
  description = "Service account name"
  value       = kubernetes_service_account_v1.eks_rag_sa.metadata[0].name
}

output "namespace" {
  description = "Namespace"
  value       = var.namespace
}
