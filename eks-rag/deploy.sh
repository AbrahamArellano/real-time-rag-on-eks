#!/bin/bash

# Set up ECR repository path
echo "Setting up ECR repository path..."
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export AWS_REGION=us-west-2
export ECR_REPO=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/advanced-rag-mloeks/eks-rag

# Create ECR repository if it doesn't exist
echo "Checking ECR repository..."
if ! aws ecr describe-repositories --repository-names advanced-rag-mloeks/eks-rag &>/dev/null; then
    echo "Creating ECR repository..."
    aws ecr create-repository --repository-name advanced-rag-mloeks/eks-rag &>/dev/null && echo "Repository created successfully"
fi

# Get ECR login token
echo "Logging into ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com &>/dev/null && echo "ECR login successful"

# Verify vLLM service accessibility
echo "Verifying vLLM service accessibility..."
if ! kubectl get svc -n vllm vllm-llama3-inf2-serve-svc &>/dev/null; then
    echo "Error: vLLM service not found in vllm namespace"
    echo "Please ensure vLLM service is deployed and accessible"
    exit 1
else
    echo "vLLM service found and accessible"
fi

# Build and push the image
echo "Building Docker image..."
docker build -t $ECR_REPO:latest . && echo "Docker image built successfully"

echo "Pushing image to ECR..."
docker push $ECR_REPO:latest && echo "Image pushed successfully"

# Process template and deploy
echo "Deploying to Kubernetes..."
envsubst < deployment.yaml | kubectl apply -f - &>/dev/null && echo "Deployment applied"
kubectl apply -f service.yaml &>/dev/null && echo "Service applied"
kubectl apply -f network-policy.yaml &>/dev/null && echo "Network policy applied"

# Wait for deployment
echo "Waiting for deployment..."
if kubectl rollout status deployment/eks-rag --timeout=300s &>/dev/null; then
    echo "Deployment completed successfully"
else
    echo "Deployment failed or timed out"
    exit 1
fi

# Show status (with formatted output)
echo -e "\nDeployment Status:"
echo "==================="
echo -e "\nDeployments:"
kubectl get deployments -o custom-columns=NAME:.metadata.name,READY:.status.readyReplicas,AVAILABLE:.status.availableReplicas,UP-TO-DATE:.status.updatedReplicas

echo -e "\nPods:"
kubectl get pods -o custom-columns=NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[0].ready

echo -e "\nServices:"
kubectl get services -o custom-columns=NAME:.metadata.name,TYPE:.spec.type,CLUSTER-IP:.spec.clusterIP,EXTERNAL-IP:.status.loadBalancer.ingress[0].hostname

echo -e "\nDeployment complete!"
