# Data sources
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# Verify vLLM service exists
data "kubernetes_service" "vllm" {
  metadata {
    name      = var.vllm_service_name
    namespace = var.vllm_namespace
  }
}

# Local variables
locals {
  account_id           = data.aws_caller_identity.current.account_id
  vllm_host            = "${var.vllm_service_name}.${var.vllm_namespace}.svc.cluster.local"
  ecr_registry         = "${local.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
  full_repository_name = var.ecr_repository_name
}

# Module 1: ECR Repository
module "ecr" {
  source = "./modules/ecr"

  repository_name = var.ecr_repository_name
  aws_region      = var.aws_region
}

# Module 2: IAM (IRSA) - Create role first without OpenSearch ARN
module "iam" {
  source = "./modules/iam"

  cluster_name            = var.cluster_name
  cluster_oidc_issuer_url = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  namespace               = var.namespace
  service_account_name    = var.service_account_name
  aws_region              = var.aws_region
  account_id              = local.account_id
}

# Module 3: OpenSearch Serverless - Uses IAM role ARN
module "opensearch" {
  source = "./modules/opensearch"

  collection_name       = var.collection_name
  iam_role_arn          = module.iam.role_arn
  allow_public_access   = var.allow_public_opensearch
  aws_region            = var.aws_region
  additional_principals = [data.aws_caller_identity.current.arn]

  depends_on = [module.iam]
}

# Docker Build and Push
resource "null_resource" "docker_build_push" {
  triggers = {
    dockerfile_hash = filemd5("${path.module}/${var.docker_build_context}/Dockerfile")
    source_hash     = sha256(join("", [for f in fileset("${path.module}/${var.docker_build_context}", "*.py") : filemd5("${path.module}/${var.docker_build_context}/${f}")]))
    ecr_url         = module.ecr.repository_url
    platform        = "linux/amd64" # Force rebuild when platform changes
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/build-and-push.sh"
    working_dir = path.module
    environment = {
      AWS_REGION    = var.aws_region
      ECR_REPO      = module.ecr.repository_url
      BUILD_CONTEXT = "${path.module}/${var.docker_build_context}"
    }
  }

  depends_on = [module.ecr]
}

# Module 4: Kubernetes Resources
module "kubernetes" {
  source = "./modules/kubernetes"

  namespace                = var.namespace
  service_account_name     = var.service_account_name
  service_account_role_arn = module.iam.role_arn
  ecr_image_url            = "${module.ecr.repository_url}:latest"
  vllm_service_host        = local.vllm_host
  vllm_service_port        = var.vllm_port
  vllm_namespace           = var.vllm_namespace
  replicas                 = var.replicas

  depends_on = [
    module.iam,
    module.ecr,
    null_resource.docker_build_push
  ]
}

# Module 5: Lambda Layers
module "lambda_layers" {
  source = "./modules/lambda-layers"

  layers_source_dir = "${path.module}/../../pythonLambdaLayers"
}

# Module 6: Kinesis Data Stream
module "kinesis" {
  source = "./modules/kinesis"

  stream_name = "error-logs-stream"
}

# Module 7: OpenSearch Index Creation
module "opensearch_index" {
  source = "./modules/opensearch-index"

  opensearch_endpoint      = module.opensearch.collection_endpoint
  opensearch_collection_id = module.opensearch.collection_id
  data_access_policy_id    = module.opensearch.data_access_policy_id
  index_name               = "error-logs-mock"
  aws_region               = var.aws_region

  depends_on = [module.opensearch]
}

# Module 8: Lambda Producer (generates vehicle logs to Kinesis)
module "lambda_producer" {
  source = "./modules/lambda-producer"

  kinesis_stream_name = module.kinesis.stream_name
  schedule_expression = "rate(1 minute)"
  logs_per_invocation = 100
  aws_region          = var.aws_region
  account_id          = local.account_id

  depends_on = [module.kinesis]
}

# Module 9: Lambda Consumer (Kinesis -> Bedrock -> OpenSearch)
module "lambda_consumer" {
  source = "./modules/lambda-consumer"

  kinesis_stream_arn        = module.kinesis.stream_arn
  opensearch_endpoint       = module.opensearch.collection_endpoint
  opensearch_collection_arn = module.opensearch.collection_arn
  index_name                = "error-logs-mock"
  aws4auth_layer_arn        = module.lambda_layers.aws4auth_layer_arn
  opensearch_layer_arn      = module.lambda_layers.opensearch_layer_arn
  aws_region                = var.aws_region
  account_id                = local.account_id

  depends_on = [module.kinesis, module.opensearch_index, module.lambda_layers]
}

# Update OpenSearch access policy to include Lambda Consumer role
resource "null_resource" "update_opensearch_policy" {
  triggers = {
    lambda_role_arn = module.lambda_consumer.lambda_role_arn
    collection_name = var.collection_name
    policy_name     = "${var.collection_name}-access"
    eks_role_arn    = module.iam.role_arn
    user_arn        = data.aws_caller_identity.current.arn
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws opensearchserverless update-access-policy \
        --name ${var.collection_name}-access \
        --type data \
        --policy-version $(aws opensearchserverless get-access-policy --name ${var.collection_name}-access --type data --query 'accessPolicyDetail.policyVersion' --output text) \
        --policy '[{"Rules":[{"ResourceType":"collection","Resource":["collection/${var.collection_name}"],"Permission":["aoss:CreateCollectionItems","aoss:DeleteCollectionItems","aoss:UpdateCollectionItems","aoss:DescribeCollectionItems"]},{"ResourceType":"index","Resource":["index/${var.collection_name}/*"],"Permission":["aoss:CreateIndex","aoss:DeleteIndex","aoss:UpdateIndex","aoss:DescribeIndex","aoss:ReadDocument","aoss:WriteDocument"]}],"Principal":["${module.iam.role_arn}","${data.aws_caller_identity.current.arn}","${module.lambda_consumer.lambda_role_arn}"]}]'
    EOT
  }

  depends_on = [module.opensearch, module.lambda_consumer]
}

# Module 10: ECR Repository for UI
module "ecr_ui" {
  source = "./modules/ecr-ui"

  repository_name = "${var.ecr_repository_name}-ui"
  aws_region      = var.aws_region
}

# Docker Build and Push for UI
resource "null_resource" "docker_build_push_ui" {
  triggers = {
    dockerfile_hash = filemd5("${path.module}/../../ui/Dockerfile")
    source_hash     = filemd5("${path.module}/../../ui/app.py")
    ecr_url         = module.ecr_ui.repository_url
    platform        = "linux/amd64"
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/build-and-push-ui.sh"
    working_dir = path.module
    environment = {
      AWS_REGION    = var.aws_region
      ECR_REPO      = module.ecr_ui.repository_url
      BUILD_CONTEXT = "${path.module}/../../ui"
    }
  }

  depends_on = [module.ecr_ui]
}

# Module 11: Gradio UI
module "ui" {
  source = "./modules/ui"

  namespace        = var.namespace
  ecr_image_url    = "${module.ecr_ui.repository_url}:latest"
  rag_service_host = "eks-rag-service"
  replicas         = 1

  depends_on = [
    module.ecr_ui,
    module.kubernetes,
    null_resource.docker_build_push_ui
  ]
}

# Print deployment summary after everything is complete
resource "null_resource" "print_summary" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOT
      echo ""
      echo "╔════════════════════════════════════════════════════════════════════════════════╗"
      echo "║                     🎉 DEPLOYMENT SUCCESSFUL!                                  ║"
      echo "╚════════════════════════════════════════════════════════════════════════════════╝"
      echo ""
      echo "📊 DEPLOYMENT STATUS:"
      echo "────────────────────────────────────────────────────────────────────────────────"
      echo "✅ RAG Backend:     ${module.kubernetes.service_endpoint}"
      echo "✅ OpenSearch:      ${module.opensearch.collection_endpoint}"
      echo "✅ Kinesis Stream:  ${module.kinesis.stream_name}"
      echo "✅ Lambda Producer: ${module.lambda_producer.lambda_function_name}"
      echo "✅ Lambda Consumer: ${module.lambda_consumer.lambda_function_name}"
      echo ""
      echo "🌐 GRADIO UI ACCESS:"
      echo "────────────────────────────────────────────────────────────────────────────────"
      echo "⏳ ALB is provisioning (2-4 minutes)..."
      echo ""
      echo "To check ALB status:"
      echo "  kubectl get ingress gradio-app-ingress"
      echo ""
      echo "Once ready, get URL with:"
      echo "  terraform output ui_url"
      echo ""
      echo "Or watch for ALB:"
      echo "  watch kubectl get ingress gradio-app-ingress"
      echo ""
      echo "📝 NEXT STEPS:"
      echo "────────────────────────────────────────────────────────────────────────────────"
      echo "1. Wait for ALB (2-4 minutes)"
      echo "2. Access UI: terraform output ui_url"
      echo "3. Monitor indexing: aws logs tail /aws/lambda/vehicle-log-consumer --region ${var.aws_region} --follow"
      echo ""
      echo "For full deployment summary:"
      echo "  terraform output deployment_summary"
      echo ""
      echo "════════════════════════════════════════════════════════════════════════════════"
      echo ""
    EOT
  }

  depends_on = [
    module.ui,
    module.kubernetes,
    module.lambda_consumer,
    module.lambda_producer,
    null_resource.update_opensearch_policy
  ]
}
