variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
}

variable "service_account_name" {
  description = "Kubernetes service account name"
  type        = string
}

variable "service_account_role_arn" {
  description = "IAM role ARN to annotate on the service account"
  type        = string
}

variable "ecr_image_url" {
  description = "Full ECR image URL with tag"
  type        = string
}

variable "vllm_service_host" {
  description = "vLLM service hostname"
  type        = string
}

variable "vllm_service_port" {
  description = "vLLM service port"
  type        = number
}

variable "vllm_namespace" {
  description = "vLLM namespace for network policy"
  type        = string
}

variable "replicas" {
  description = "Number of replicas"
  type        = number
  default     = 2
}
