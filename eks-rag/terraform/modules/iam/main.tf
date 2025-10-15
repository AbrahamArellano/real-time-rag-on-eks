data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
}

# IAM Policy for Bedrock access
resource "aws_iam_policy" "bedrock_policy" {
  name        = "eks-rag-bedrock-policy"
  description = "Policy for EKS RAG service to access Bedrock"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel"
        ]
        Resource = "arn:aws:bedrock:${var.aws_region}::foundation-model/cohere.embed-english-v3"
      }
    ]
  })
}

# IAM Policy for OpenSearch Serverless access
resource "aws_iam_policy" "opensearch_policy" {
  name        = "eks-rag-opensearch-policy"
  description = "Policy for EKS RAG service to access OpenSearch Serverless"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "aoss:APIAccessAll",
          "aoss:DashboardsAccessAll"
        ]
        Resource = "arn:aws:aoss:${var.aws_region}:${var.account_id}:collection/*"
      },
      {
        Effect = "Allow"
        Action = [
          "aoss:ListCollections",
          "aoss:BatchGetCollection"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM Role for Service Account (Pod Identity)
resource "aws_iam_role" "eks_rag_sa" {
  name = "eks-rag-sa-role-${var.cluster_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "pods.eks.amazonaws.com"
        }
        Action = [
          "sts:AssumeRole",
          "sts:TagSession"
        ]
      }
    ]
  })

  tags = {
    Name           = "eks-rag-sa-role"
    Cluster        = var.cluster_name
    ServiceAccount = var.service_account_name
  }
}

# Attach Bedrock policy to role
resource "aws_iam_role_policy_attachment" "bedrock_attach" {
  role       = aws_iam_role.eks_rag_sa.name
  policy_arn = aws_iam_policy.bedrock_policy.arn
}

# Attach OpenSearch policy to role
resource "aws_iam_role_policy_attachment" "opensearch_attach" {
  role       = aws_iam_role.eks_rag_sa.name
  policy_arn = aws_iam_policy.opensearch_policy.arn
}

# EKS Pod Identity Association
resource "aws_eks_pod_identity_association" "eks_rag" {
  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = var.service_account_name
  role_arn        = aws_iam_role.eks_rag_sa.arn

  tags = {
    Name = "eks-rag-pod-identity"
  }
}
