variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "trainium-inferentia"
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "namespace" {
  description = "Kubernetes namespace for deployment"
  type        = string
  default     = "default"
}

variable "collection_name" {
  description = "OpenSearch Serverless collection name"
  type        = string
  default     = "error-logs-mock"
}

variable "service_account_name" {
  description = "Kubernetes service account name"
  type        = string
  default     = "eks-rag-sa"
}

variable "vllm_service_name" {
  description = "vLLM service name"
  type        = string
  default     = "vllm-llama3-inf2-serve-svc"
}

variable "vllm_namespace" {
  description = "vLLM service namespace"
  type        = string
  default     = "vllm"
}

variable "vllm_port" {
  description = "vLLM service port"
  type        = number
  default     = 8000
}

variable "replicas" {
  description = "Number of RAG service replicas"
  type        = number
  default     = 2
}

variable "allow_public_opensearch" {
  description = "Allow public access to OpenSearch collection"
  type        = bool
  default     = true
}

variable "ecr_repository_name" {
  description = "ECR repository name for RAG service"
  type        = string
  default     = "advanced-rag-mloeks/eks-rag"
}

variable "docker_build_context" {
  description = "Path to Docker build context (relative to terraform directory)"
  type        = string
  default     = ".."
}

variable "opensearch_scripts_path" {
  description = "Path to opensearch-setup scripts (relative to terraform directory)"
  type        = string
  default     = "../../opensearch-setup"
}
