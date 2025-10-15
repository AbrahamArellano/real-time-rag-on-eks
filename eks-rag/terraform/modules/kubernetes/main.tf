# Service Account (Pod Identity - no annotation needed)
resource "kubernetes_service_account_v1" "eks_rag_sa" {
  metadata {
    name      = var.service_account_name
    namespace = var.namespace
  }
}

# Deployment
resource "kubernetes_deployment_v1" "eks_rag" {
  metadata {
    name      = "eks-rag"
    namespace = var.namespace
    labels = {
      app = "eks-rag"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = "eks-rag"
      }
    }

    template {
      metadata {
        labels = {
          app = "eks-rag"
        }
      }

      spec {
        service_account_name = kubernetes_service_account_v1.eks_rag_sa.metadata[0].name

        container {
          name              = "eks-rag"
          image             = var.ecr_image_url
          image_pull_policy = "Always"

          port {
            container_port = 5000
          }

          env {
            name  = "VLLM_HOST"
            value = var.vllm_service_host
          }

          env {
            name  = "VLLM_PORT"
            value = tostring(var.vllm_service_port)
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 30
            timeout_seconds       = 10
            period_seconds        = 15
          }

          liveness_probe {
            http_get {
              path = "/health"
              port = 5000
            }
            initial_delay_seconds = 60
            timeout_seconds       = 10
            period_seconds        = 20
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service_account_v1.eks_rag_sa]
}

# Service (ClusterIP - internal only, accessed by UI)
resource "kubernetes_service_v1" "eks_rag_service" {
  metadata {
    name      = "eks-rag-service"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "eks-rag"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 5000
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment_v1.eks_rag]
}

# Network Policy - Allow egress to vLLM namespace
resource "kubernetes_network_policy_v1" "allow_vllm_access" {
  metadata {
    name      = "allow-vllm-access"
    namespace = var.namespace
  }

  spec {
    pod_selector {
      match_labels = {
        app = "eks-rag"
      }
    }

    policy_types = ["Egress"]

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = var.vllm_namespace
          }
        }
      }

      ports {
        protocol = "TCP"
        port     = tostring(var.vllm_service_port)
      }
    }

    # Allow DNS resolution
    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
      }

      ports {
        protocol = "UDP"
        port     = "53"
      }
    }

    # Allow access to AWS services (for Bedrock and OpenSearch)
    egress {
      to {
        ip_block {
          cidr = "0.0.0.0/0"
        }
      }

      ports {
        protocol = "TCP"
        port     = "443"
      }
    }
  }

  depends_on = [kubernetes_deployment_v1.eks_rag]
}
