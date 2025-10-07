#!/bin/bash

echo "Starting cleanup process..."

# Delete Kubernetes resources
echo "Deleting Kubernetes service..."
kubectl delete service eks-rag-service --ignore-not-found
echo "Deleting Kubernetes deployment..."
kubectl delete deployment eks-rag --ignore-not-found
echo "Deleting Network Policy..."
kubectl delete networkpolicy allow-vllm-access --ignore-not-found

# Delete ECR images
echo "Checking ECR repository..."
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=us-west-2
REPO_NAME=advanced-rag-mloeks/eks-rag

# Check if repository exists
if aws ecr describe-repositories --repository-names $REPO_NAME 2>/dev/null; then
    echo "Found ECR repository, deleting images..."
    IMAGE_IDS=$(aws ecr list-images --repository-name $REPO_NAME --query 'imageIds[*]' --output json)
    
    if [ "$IMAGE_IDS" != "[]" ] && [ "$IMAGE_IDS" != "" ]; then
        echo "Deleting images..."
        aws ecr batch-delete-image --repository-name $REPO_NAME --image-ids "$IMAGE_IDS"
    else
        echo "No images found in repository"
    fi
else
    echo "ECR repository does not exist, skipping image cleanup"
fi

echo "Cleanup complete!"
