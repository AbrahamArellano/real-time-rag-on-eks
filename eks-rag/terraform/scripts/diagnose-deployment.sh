#!/bin/bash

echo "=========================================="
echo "Deployment Diagnostics"
echo "=========================================="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}1. TERRAFORM STATE${NC}"
echo "===================="
terraform output
echo ""

echo -e "${BLUE}2. KUBERNETES RESOURCES${NC}"
echo "========================"
echo ""
echo "Pods:"
kubectl get pods -l app=eks-rag -o wide
echo ""
echo "Deployment:"
kubectl get deployment eks-rag
echo ""
echo "Service Account:"
kubectl get sa eks-rag-sa -o yaml | grep -A 5 "annotations:"
echo ""
echo "Service:"
kubectl get svc eks-rag-service
echo ""
echo "NetworkPolicy:"
kubectl get networkpolicy allow-vllm-access
echo ""

echo -e "${BLUE}3. POD STATUS DETAILS${NC}"
echo "======================"
PODS=$(kubectl get pods -l app=eks-rag -o jsonpath='{.items[*].metadata.name}')
if [ -z "$PODS" ]; then
    echo -e "${RED}No pods found!${NC}"
else
    for POD in $PODS; do
        echo ""
        echo -e "${YELLOW}Pod: $POD${NC}"
        echo "---"
        kubectl get pod $POD -o jsonpath='{.status.phase}' && echo ""
        kubectl get pod $POD -o jsonpath='{.status.conditions}' | jq .
        echo ""
    done
fi
echo ""

echo -e "${BLUE}4. POD EVENTS${NC}"
echo "=============="
if [ ! -z "$PODS" ]; then
    for POD in $PODS; do
        echo ""
        echo -e "${YELLOW}Events for $POD:${NC}"
        kubectl describe pod $POD | grep -A 20 "Events:"
    done
else
    echo "Checking deployment events:"
    kubectl describe deployment eks-rag | grep -A 20 "Events:"
fi
echo ""

echo -e "${BLUE}5. POD LOGS${NC}"
echo "==========="
if [ ! -z "$PODS" ]; then
    for POD in $PODS; do
        echo ""
        echo -e "${YELLOW}Logs for $POD:${NC}"
        kubectl logs $POD --tail=50 2>&1 || echo "Pod not ready for logs"
    done
else
    echo -e "${RED}No pods to get logs from${NC}"
fi
echo ""

echo -e "${BLUE}6. IAM ROLE VERIFICATION${NC}"
echo "========================="
ROLE_ARN=$(terraform output -raw service_account_role_arn 2>/dev/null)
echo "Role ARN from Terraform: $ROLE_ARN"
echo ""
echo "ServiceAccount annotation:"
kubectl get sa eks-rag-sa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}' && echo ""
echo ""
echo "Checking IAM role exists:"
aws iam get-role --role-name eks-rag-sa-role-trainium-inferentia --query 'Role.Arn' --output text 2>&1
echo ""
echo "Checking attached policies:"
aws iam list-attached-role-policies --role-name eks-rag-sa-role-trainium-inferentia --output json 2>&1 | jq -r '.AttachedPolicies[].PolicyName'
echo ""

echo -e "${BLUE}7. OPENSEARCH COLLECTION${NC}"
echo "========================"
COLLECTION_ID=$(terraform output -raw opensearch_collection_id 2>/dev/null)
echo "Collection ID: $COLLECTION_ID"
echo ""
echo "Collection status:"
aws opensearchserverless batch-get-collection --ids $COLLECTION_ID --region us-west-2 --query 'collectionDetails[0].{Name:name,Status:status,Endpoint:collectionEndpoint}' --output json 2>&1 | jq .
echo ""

echo -e "${BLUE}8. ECR IMAGE${NC}"
echo "============"
ECR_REPO=$(terraform output -raw ecr_repository_url 2>/dev/null)
echo "Repository: $ECR_REPO"
echo ""
echo "Image tags:"
aws ecr list-images --repository-name advanced-rag-mloeks/eks-rag --region us-west-2 --query 'imageIds[*].imageTag' --output json 2>&1 | jq -r '.[]'
echo ""
echo "Latest image details:"
aws ecr describe-images --repository-name advanced-rag-mloeks/eks-rag --region us-west-2 --image-ids imageTag=latest --query 'imageDetails[0].{Pushed:imagePushedAt,Size:imageSizeInBytes,Digest:imageDigest}' --output json 2>&1 | jq .
echo ""

echo -e "${BLUE}9. VLLM SERVICE CONNECTIVITY${NC}"
echo "============================"
echo "vLLM service:"
kubectl get svc -n vllm vllm-llama3-inf2-serve-svc
echo ""
echo "Testing connectivity from a pod (if available):"
if [ ! -z "$PODS" ]; then
    FIRST_POD=$(echo $PODS | awk '{print $1}')
    kubectl exec -it $FIRST_POD -- curl -s -m 5 http://vllm-llama3-inf2-serve-svc.vllm.svc.cluster.local:8000/health 2>&1 || echo "Cannot test - pod not ready"
else
    echo "No pods available to test from"
fi
echo ""

echo -e "${BLUE}10. DATA INDEXING STATUS${NC}"
echo "========================"
echo "Checking if error_logs.json was generated:"
ls -lh ../../opensearch-setup/error_logs.json 2>&1
echo ""
echo "Number of logs generated:"
cat ../../opensearch-setup/error_logs.json 2>/dev/null | jq '. | length' 2>&1
echo ""

echo -e "${BLUE}11. NETWORK POLICY${NC}"
echo "=================="
kubectl get networkpolicy allow-vllm-access -o yaml
echo ""

echo -e "${BLUE}12. RECOMMENDED ACTIONS${NC}"
echo "======================="
echo ""

# Analyze issues
ISSUE_COUNT=0

if [ -z "$PODS" ]; then
    echo -e "${RED}✗ No pods found - Deployment failed to create pods${NC}"
    ISSUE_COUNT=$((ISSUE_COUNT+1))
    echo "  → Check deployment events above"
    echo "  → Check if image pull succeeded"
fi

if kubectl get pods -l app=eks-rag -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q "Pending"; then
    echo -e "${YELLOW}⚠ Pods are Pending${NC}"
    ISSUE_COUNT=$((ISSUE_COUNT+1))
    echo "  → Check pod events for scheduling issues"
    echo "  → Verify node resources available"
fi

if kubectl get pods -l app=eks-rag -o jsonpath='{.items[*].status.phase}' 2>/dev/null | grep -q "CrashLoopBackOff"; then
    echo -e "${RED}✗ Pods are CrashLoopBackOff${NC}"
    ISSUE_COUNT=$((ISSUE_COUNT+1))
    echo "  → Check pod logs above"
    echo "  → Likely issues: OpenSearch connection, IAM permissions, vLLM connectivity"
fi

if kubectl get pods -l app=eks-rag -o jsonpath='{.items[*].status.containerStatuses[*].ready}' 2>/dev/null | grep -q "false"; then
    echo -e "${YELLOW}⚠ Pods are not Ready${NC}"
    ISSUE_COUNT=$((ISSUE_COUNT+1))
    echo "  → Check readiness probe: /health endpoint"
    echo "  → Check pod logs for startup errors"
fi

if [ $ISSUE_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ No obvious issues detected${NC}"
    echo "  → Pods may still be starting (check ages)"
    echo "  → Wait for readiness probes to pass"
fi

echo ""
echo "=========================================="
echo "Diagnostics Complete"
echo "=========================================="
