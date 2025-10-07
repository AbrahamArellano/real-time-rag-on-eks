# Gradio UI Deployment
resource "kubernetes_deployment_v1" "gradio_ui" {
  metadata {
    name      = "gradio-app"
    namespace = var.namespace
    labels = {
      app = "gradio-app"
    }
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = {
        app = "gradio-app"
      }
    }

    template {
      metadata {
        labels = {
          app = "gradio-app"
        }
      }

      spec {
        container {
          name  = "gradio-app"
          image = var.ecr_image_url

          port {
            container_port = 7860
          }

          env {
            name  = "RAG_SERVICE_HOST"
            value = var.rag_service_host
          }

          resources {
            requests = {
              cpu    = "500m"
              memory = "500Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "500Mi"
            }
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 7860
            }
            initial_delay_seconds = 30
            period_seconds        = 10
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 7860
            }
            initial_delay_seconds = 60
            period_seconds        = 15
          }
        }
      }
    }
  }
}

# ClusterIP Service for internal access
resource "kubernetes_service_v1" "gradio_service" {
  metadata {
    name      = "gradio-app"
    namespace = var.namespace
  }

  spec {
    selector = {
      app = "gradio-app"
    }

    port {
      protocol    = "TCP"
      port        = 80
      target_port = 7860
    }

    type = "ClusterIP"
  }

  depends_on = [kubernetes_deployment_v1.gradio_ui]
}

# ALB Ingress for internet-facing access
resource "kubernetes_ingress_v1" "gradio_ingress" {
  metadata {
    name      = "gradio-app-ingress"
    namespace = var.namespace

    annotations = {
      "alb.ingress.kubernetes.io/scheme"                       = "internet-facing"
      "alb.ingress.kubernetes.io/target-type"                  = "ip"
      "alb.ingress.kubernetes.io/healthcheck-path"             = "/"
      "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = "10"
      "alb.ingress.kubernetes.io/healthcheck-timeout-seconds"  = "9"
      "alb.ingress.kubernetes.io/healthy-threshold-count"      = "2"
      "alb.ingress.kubernetes.io/unhealthy-threshold-count"    = "10"
      "alb.ingress.kubernetes.io/success-codes"                = "200-302"
      "alb.ingress.kubernetes.io/load-balancer-name"           = "gradio-app-ingress"
    }

    labels = {
      app = "gradio-app-ingress"
    }
  }

  spec {
    ingress_class_name = "alb"

    rule {
      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.gradio_service.metadata[0].name
              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }

  depends_on = [kubernetes_service_v1.gradio_service]
}
