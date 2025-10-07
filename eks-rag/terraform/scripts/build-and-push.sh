#!/bin/bash
set -e

echo "=========================================="
echo "Docker Build and Push to ECR"
echo "=========================================="

# Validate environment variables
if [ -z "$AWS_REGION" ] || [ -z "$ECR_REPO" ] || [ -z "$BUILD_CONTEXT" ]; then
    echo "Error: Required environment variables not set"
    echo "  AWS_REGION: $AWS_REGION"
    echo "  ECR_REPO: $ECR_REPO"
    echo "  BUILD_CONTEXT: $BUILD_CONTEXT"
    exit 1
fi

echo "AWS Region: $AWS_REGION"
echo "ECR Repository: $ECR_REPO"
echo "Build Context: $BUILD_CONTEXT"

# Extract account ID and region from ECR repo URL
ACCOUNT_ID=$(echo $ECR_REPO | cut -d'.' -f1)
ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

echo ""
echo "Step 1: Authenticating with ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
if [ $? -ne 0 ]; then
    echo "Error: Failed to authenticate with ECR"
    exit 1
fi
echo "✓ ECR authentication successful"

echo ""
echo "Step 2: Building Docker image for linux/amd64 platform..."
docker build --platform linux/amd64 -t $ECR_REPO:latest $BUILD_CONTEXT
if [ $? -ne 0 ]; then
    echo "Error: Docker build failed"
    echo "Note: If buildx is not available, trying legacy build..."
    docker build -t $ECR_REPO:latest $BUILD_CONTEXT
    if [ $? -ne 0 ]; then
        echo "Error: Docker build failed with both methods"
        exit 1
    fi
fi
echo "✓ Docker image built successfully for linux/amd64"

echo ""
echo "Step 3: Pushing image to ECR..."
docker push $ECR_REPO:latest
if [ $? -ne 0 ]; then
    echo "Error: Failed to push image to ECR"
    exit 1
fi
echo "✓ Image pushed successfully"

echo ""
echo "=========================================="
echo "Build and Push Complete!"
echo "Image: $ECR_REPO:latest"
echo "=========================================="
