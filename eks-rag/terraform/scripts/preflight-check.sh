#!/bin/bash

echo "=========================================="
echo "Terraform Deployment Pre-flight Check"
echo "=========================================="
echo ""

ERRORS=0
WARNINGS=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check functions
check_command() {
    if command -v $1 &> /dev/null; then
        echo -e "${GREEN}✓${NC} $1 is installed"
        return 0
    else
        echo -e "${RED}✗${NC} $1 is NOT installed"
        ERRORS=$((ERRORS+1))
        return 1
    fi
}

check_version() {
    local cmd=$1
    local version=$2
    local min_version=$3

    if [ -z "$version" ]; then
        echo -e "${YELLOW}⚠${NC} Could not determine $cmd version"
        WARNINGS=$((WARNINGS+1))
        return 1
    fi

    echo -e "${GREEN}✓${NC} $cmd version: $version"
    return 0
}

# 1. Check Terraform
echo "1. Checking Terraform..."
if check_command terraform; then
    TF_VERSION=$(terraform version -json 2>/dev/null | grep -o '"terraform_version":"[^"]*' | cut -d'"' -f4)
    check_version "Terraform" "$TF_VERSION" "1.5.0"
fi
echo ""

# 2. Check AWS CLI
echo "2. Checking AWS CLI..."
if check_command aws; then
    AWS_VERSION=$(aws --version 2>&1 | cut -d' ' -f1 | cut -d'/' -f2)
    check_version "AWS CLI" "$AWS_VERSION" "2.0.0"

    # Check AWS credentials
    if aws sts get-caller-identity &> /dev/null; then
        ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        echo -e "${GREEN}✓${NC} AWS credentials are configured (Account: $ACCOUNT_ID)"
    else
        echo -e "${RED}✗${NC} AWS credentials are NOT configured"
        ERRORS=$((ERRORS+1))
    fi
fi
echo ""

# 3. Check kubectl
echo "3. Checking kubectl..."
if check_command kubectl; then
    KUBECTL_VERSION=$(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*' | head -1 | cut -d'"' -f4)
    check_version "kubectl" "$KUBECTL_VERSION" "1.28.0"

    # Check cluster access
    if kubectl cluster-info &> /dev/null; then
        CLUSTER_NAME=$(kubectl config current-context)
        echo -e "${GREEN}✓${NC} kubectl is configured (Context: $CLUSTER_NAME)"
    else
        echo -e "${RED}✗${NC} kubectl is NOT configured or cluster is unreachable"
        ERRORS=$((ERRORS+1))
    fi
fi
echo ""

# 4. Check Docker
echo "4. Checking Docker..."
if check_command docker; then
    DOCKER_VERSION=$(docker version --format '{{.Server.Version}}' 2>/dev/null)
    check_version "Docker" "$DOCKER_VERSION" "20.0.0"

    # Check Docker daemon
    if docker ps &> /dev/null; then
        echo -e "${GREEN}✓${NC} Docker daemon is running"
    else
        echo -e "${RED}✗${NC} Docker daemon is NOT running"
        ERRORS=$((ERRORS+1))
    fi
fi
echo ""

# 5. Check Python
echo "5. Checking Python..."
if check_command python3; then
    PYTHON_VERSION=$(python3 --version 2>&1 | cut -d' ' -f2)
    check_version "Python" "$PYTHON_VERSION" "3.9.0"

    # Check pip
    if check_command pip3; then
        PIP_VERSION=$(pip3 --version 2>&1 | cut -d' ' -f2)
        echo -e "${GREEN}✓${NC} pip version: $PIP_VERSION"
    fi
fi
echo ""

# 6. Check EKS Cluster
echo "6. Checking EKS Cluster..."
CLUSTER_NAME="trainium-inferentia"
if aws eks describe-cluster --name $CLUSTER_NAME --region us-west-2 &> /dev/null; then
    CLUSTER_STATUS=$(aws eks describe-cluster --name $CLUSTER_NAME --region us-west-2 --query 'cluster.status' --output text)
    if [ "$CLUSTER_STATUS" = "ACTIVE" ]; then
        echo -e "${GREEN}✓${NC} EKS cluster '$CLUSTER_NAME' is ACTIVE"
    else
        echo -e "${YELLOW}⚠${NC} EKS cluster '$CLUSTER_NAME' status: $CLUSTER_STATUS"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "${RED}✗${NC} EKS cluster '$CLUSTER_NAME' not found or not accessible"
    ERRORS=$((ERRORS+1))
fi
echo ""

# 7. Check vLLM Service
echo "7. Checking vLLM Service..."
if kubectl get svc -n vllm vllm-llama3-inf2-serve-svc &> /dev/null; then
    VLLM_IP=$(kubectl get svc -n vllm vllm-llama3-inf2-serve-svc -o jsonpath='{.spec.clusterIP}')
    VLLM_PORT=$(kubectl get svc -n vllm vllm-llama3-inf2-serve-svc -o jsonpath='{.spec.ports[0].port}')
    echo -e "${GREEN}✓${NC} vLLM service found (ClusterIP: $VLLM_IP:$VLLM_PORT)"
else
    echo -e "${RED}✗${NC} vLLM service 'vllm-llama3-inf2-serve-svc' not found in 'vllm' namespace"
    ERRORS=$((ERRORS+1))
fi
echo ""

# 8. Check vLLM Pods
echo "8. Checking vLLM Pods..."
VLLM_PODS=$(kubectl get pods -n vllm -l app.kubernetes.io/component=ray-head -o jsonpath='{.items[*].status.phase}' 2>/dev/null)
if [ ! -z "$VLLM_PODS" ]; then
    if [[ "$VLLM_PODS" == *"Running"* ]]; then
        echo -e "${GREEN}✓${NC} vLLM pods are running"
    else
        echo -e "${YELLOW}⚠${NC} vLLM pods status: $VLLM_PODS"
        WARNINGS=$((WARNINGS+1))
    fi
else
    echo -e "${YELLOW}⚠${NC} Could not determine vLLM pod status"
    WARNINGS=$((WARNINGS+1))
fi
echo ""

# 9. Check Python Dependencies
echo "9. Checking Python Dependencies..."
for package in boto3 opensearch-py requests-aws4auth; do
    if pip3 list 2>/dev/null | grep -i "^${package}" &> /dev/null; then
        echo -e "${GREEN}✓${NC} Python package '$package' is installed"
    else
        echo -e "${YELLOW}⚠${NC} Python package '$package' is NOT installed (will be installed during deployment)"
        WARNINGS=$((WARNINGS+1))
    fi
done
echo ""

# 10. Check Existing Resources
echo "10. Checking for Existing Resources..."

# Check if ECR repo exists
if aws ecr describe-repositories --repository-names advanced-rag-mloeks/eks-rag --region us-west-2 &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} ECR repository 'advanced-rag-mloeks/eks-rag' already exists"
    WARNINGS=$((WARNINGS+1))
else
    echo -e "${GREEN}✓${NC} ECR repository does not exist (will be created)"
fi

# Check if OpenSearch collection exists
if aws opensearchserverless list-collections --region us-west-2 2>/dev/null | grep -q "error-logs-mock"; then
    echo -e "${YELLOW}⚠${NC} OpenSearch collection 'error-logs-mock' already exists"
    WARNINGS=$((WARNINGS+1))
else
    echo -e "${GREEN}✓${NC} OpenSearch collection does not exist (will be created)"
fi

# Check if Kubernetes resources exist
if kubectl get deployment eks-rag -n default &> /dev/null; then
    echo -e "${YELLOW}⚠${NC} Kubernetes deployment 'eks-rag' already exists"
    WARNINGS=$((WARNINGS+1))
else
    echo -e "${GREEN}✓${NC} Kubernetes deployment does not exist (will be created)"
fi

echo ""
echo "=========================================="
echo "Pre-flight Check Summary"
echo "=========================================="

if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}✓ All checks passed! Ready to deploy.${NC}"
    echo ""
    echo "Next steps:"
    echo "  1. cd eks-rag/terraform"
    echo "  2. terraform init"
    echo "  3. terraform plan"
    echo "  4. terraform apply"
    exit 0
elif [ $ERRORS -eq 0 ]; then
    echo -e "${YELLOW}⚠ Checks passed with $WARNINGS warning(s)${NC}"
    echo ""
    echo "You can proceed with deployment, but review the warnings above."
    echo ""
    echo "Next steps:"
    echo "  1. cd eks-rag/terraform"
    echo "  2. terraform init"
    echo "  3. terraform plan"
    echo "  4. terraform apply"
    exit 0
else
    echo -e "${RED}✗ Pre-flight check failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    echo ""
    echo "Please resolve the errors above before proceeding with deployment."
    exit 1
fi
