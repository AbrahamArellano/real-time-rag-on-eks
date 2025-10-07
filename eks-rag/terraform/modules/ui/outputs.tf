output "deployment_name" {
  description = "UI deployment name"
  value       = kubernetes_deployment_v1.gradio_ui.metadata[0].name
}

output "service_name" {
  description = "UI service name"
  value       = kubernetes_service_v1.gradio_service.metadata[0].name
}

output "alb_hostname" {
  description = "ALB hostname for accessing the UI"
  value       = try(kubernetes_ingress_v1.gradio_ingress.status[0].load_balancer[0].ingress[0].hostname, "pending")
}

output "ingress_name" {
  description = "Ingress resource name"
  value       = kubernetes_ingress_v1.gradio_ingress.metadata[0].name
}
