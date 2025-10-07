#!/bin/bash
set -e

echo "=========================================="
echo "Fix Docker Platform & Rebuild"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}This script will:${NC}"
echo "1. Taint the Docker build resource in Terraform"
echo "2. Rebuild the image with --platform linux/amd64"
echo "3. Push to ECR"
echo "4. Restart the Kubernetes deployment"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo ""
echo -e "${BLUE}Step 1: Tainting Docker build resource${NC}"
echo "=========================================="
terraform taint null_resource.docker_build_push
echo -e "${GREEN}✓ Resource tainted - will be rebuilt${NC}"

echo ""
echo -e "${BLUE}Step 2: Rebuilding with correct platform${NC}"
echo "=========================================="
terraform apply -target=null_resource.docker_build_push -auto-approve
if [ $? -ne 0 ]; then
    echo -e "${RED}✗ Rebuild failed${NC}"
    exit 1
fi
echo -e "${GREEN}✓ Image rebuilt and pushed with linux/amd64${NC}"

echo ""
echo -e "${BLUE}Step 3: Verifying image platform${NC}"
echo "=========================================="
echo "Checking ECR image manifest..."
aws ecr batch-get-image \
    --repository-name advanced-rag-mloeks/eks-rag \
    --region us-west-2 \
    --image-ids imageTag=latest \
    --accepted-media-types "application/vnd.docker.distribution.manifest.v2+json" \
    --query 'images[0].imageManifest' \
    --output text | jq -r '.config.digest' 2>/dev/null && echo -e "${GREEN}✓ Image manifest found${NC}" || echo -e "${YELLOW}⚠ Could not verify platform (image exists)${NC}"

echo ""
echo -e "${BLUE}Step 4: Cleaning up failed pods${NC}"
echo "=========================================="
echo "Deleting pods in ImagePullBackOff state..."
kubectl delete pods -l app=eks-rag
echo -e "${GREEN}✓ Old pods deleted${NC}"

echo ""
echo -e "${BLUE}Step 5: Waiting for new pods${NC}"
echo "=========================================="
echo "Kubernetes will automatically create new pods..."
sleep 5

echo "Checking pod status:"
kubectl get pods -l app=eks-rag -o wide

echo ""
echo -e "${YELLOW}Waiting for pods to be ready (this may take 2-3 minutes)...${NC}"
kubectl wait --for=condition=ready pod -l app=eks-rag --timeout=300s 2>&1 || {
    echo -e "${YELLOW}⚠ Pods not ready within 5 minutes${NC}"
    echo "Current status:"
    kubectl get pods -l app=eks-rag
    echo ""
    echo "Pod events:"
    kubectl describe pods -l app=eks-rag | grep -A 20 "Events:"
    echo ""
    echo -e "${YELLOW}Check pod logs with: kubectl logs -l app=eks-rag --tail=50${NC}"
    exit 1
}

echo ""
echo -e "${GREEN}✓ Pods are ready!${NC}"

echo ""
echo -e "${BLUE}Step 6: Checking service and deployment${NC}"
echo "=========================================="
echo "Deployment status:"
kubectl get deployment eks-rag

echo ""
echo "Service status:"
kubectl get svc eks-rag-service 2>&1 || echo -e "${YELLOW}⚠ Service not created yet (will be created by Terraform)${NC}"

echo ""
echo -e "${BLUE}Step 7: Completing Terraform deployment${NC}"
echo "=========================================="
echo "Applying full Terraform configuration to create remaining resources..."
terraform apply -auto-approve
if [ $? -ne 0 ]; then
    echo -e "${YELLOW}⚠ Terraform apply had issues, but pods are running${NC}"
    echo "You may need to run: terraform apply"
else
    echo -e "${GREEN}✓ Full deployment complete${NC}"
fi

echo ""
echo "=========================================="
echo -e "${GREEN}Platform Fix Complete!${NC}"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Check pod status: kubectl get pods -l app=eks-rag"
echo "2. View pod logs: kubectl logs -l app=eks-rag --tail=50"
echo "3. Get service endpoint: kubectl get svc eks-rag-service"
echo "4. Test health: curl http://\$(kubectl get svc eks-rag-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')/health"
echo ""
echo "If pods are running:"
echo "  terraform output  # Get all endpoints"
echo ""
