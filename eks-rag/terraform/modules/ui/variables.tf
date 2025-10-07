variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "ecr_image_url" {
  description = "ECR image URL for the UI"
  type        = string
}

variable "rag_service_host" {
  description = "RAG service hostname (internal)"
  type        = string
  default     = "eks-rag-service"
}

variable "replicas" {
  description = "Number of UI pod replicas"
  type        = number
  default     = 1
}
