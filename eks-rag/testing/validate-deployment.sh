#!/bin/bash

# Real-Time RAG Pipeline Validation Script
# Tests all components: MSK → Lambda → Bedrock → OpenSearch → RAG → UI

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$SCRIPT_DIR/../terraform"

# Get region from Terraform or use default
cd "$TERRAFORM_DIR"
TERRAFORM_REGION=$(terraform output -raw aws_region 2>/dev/null || echo "")
REGION=${AWS_REGION:-${TERRAFORM_REGION:-us-west-2}}
cd - > /dev/null

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Helper functions
print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_test() {
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo -e "${YELLOW}[TEST $TESTS_TOTAL]${NC} $1"
}

print_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✅ PASS:${NC} $1\n"
}

print_fail() {
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}❌ FAIL:${NC} $1\n"
}

print_info() {
    echo -e "${BLUE}ℹ️  INFO:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠️  WARNING:${NC} $1"
}

# Get Terraform outputs
get_terraform_output() {
    cd "$TERRAFORM_DIR"
    terraform output -raw "$1" 2>/dev/null || echo ""
}

# Start validation
print_header "Real-Time RAG Pipeline Validation"
echo "Region: $REGION"
echo "Started: $(date)"
echo ""

# Prerequisites check
print_header "STEP 1: Prerequisites"

print_test "Checking AWS credentials"
if aws sts get-caller-identity --region $REGION &>/dev/null; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    print_pass "AWS credentials valid (Account: $ACCOUNT_ID)"
else
    print_fail "AWS credentials invalid or expired"
    exit 1
fi

print_test "Checking Terraform outputs"
cd "$TERRAFORM_DIR"
if terraform output &>/dev/null; then
    print_pass "Terraform state accessible"
else
    print_fail "Cannot read Terraform outputs"
    exit 1
fi

# Get all outputs
MSK_CLUSTER_ARN=$(get_terraform_output msk_cluster_arn)
LAMBDA_PRODUCER=$(get_terraform_output lambda_producer_name)
LAMBDA_CONSUMER=$(get_terraform_output lambda_consumer_name)
OPENSEARCH_ENDPOINT=$(get_terraform_output opensearch_collection_endpoint)
RAG_SERVICE=$(get_terraform_output rag_service_endpoint)
UI_URL=$(get_terraform_output ui_url)

print_info "MSK Cluster: ${MSK_CLUSTER_ARN##*/}"
print_info "Lambda Producer: $LAMBDA_PRODUCER"
print_info "Lambda Consumer: $LAMBDA_CONSUMER"
print_info "OpenSearch: $OPENSEARCH_ENDPOINT"
print_info "UI URL: $UI_URL"

# Test MSK Cluster
print_header "STEP 2: MSK Serverless Cluster"

print_test "Checking MSK cluster status"
MSK_STATUS=$(aws kafka describe-cluster-v2 \
    --cluster-arn "$MSK_CLUSTER_ARN" \
    --region $REGION \
    --query 'ClusterInfo.State' \
    --output text 2>/dev/null)

if [ "$MSK_STATUS" == "ACTIVE" ]; then
    print_pass "MSK cluster is ACTIVE"
else
    print_fail "MSK cluster status: $MSK_STATUS (expected: ACTIVE)"
fi

print_test "Checking MSK cluster configuration"
MSK_AUTH=$(aws kafka describe-cluster-v2 \
    --cluster-arn "$MSK_CLUSTER_ARN" \
    --region $REGION \
    --query 'ClusterInfo.Serverless.ClientAuthentication.Sasl.Iam.Enabled' \
    --output text 2>/dev/null)

if [ "$MSK_AUTH" == "True" ]; then
    print_pass "MSK SASL/IAM authentication enabled"
else
    print_fail "MSK SASL/IAM authentication not enabled"
fi

# Test Lambda Producer
print_header "STEP 3: Lambda Producer Function"

print_test "Checking Lambda Producer existence"
if aws lambda get-function \
    --function-name "$LAMBDA_PRODUCER" \
    --region $REGION &>/dev/null; then
    print_pass "Lambda Producer exists"
else
    print_fail "Lambda Producer not found"
fi

print_test "Checking Lambda Producer configuration"
PRODUCER_RUNTIME=$(aws lambda get-function-configuration \
    --function-name "$LAMBDA_PRODUCER" \
    --region $REGION \
    --query 'Runtime' \
    --output text 2>/dev/null)

PRODUCER_STATE=$(aws lambda get-function-configuration \
    --function-name "$LAMBDA_PRODUCER" \
    --region $REGION \
    --query 'State' \
    --output text 2>/dev/null)

if [ "$PRODUCER_STATE" == "Active" ]; then
    print_pass "Lambda Producer is Active (Runtime: $PRODUCER_RUNTIME)"
else
    print_fail "Lambda Producer state: $PRODUCER_STATE (expected: Active)"
fi

print_test "Checking EventBridge schedule"
SCHEDULE_STATE=$(aws events describe-rule \
    --name vehicle-log-producer-schedule \
    --region $REGION \
    --query 'State' \
    --output text 2>/dev/null)

if [ "$SCHEDULE_STATE" == "ENABLED" ]; then
    SCHEDULE_EXPR=$(aws events describe-rule \
        --name vehicle-log-producer-schedule \
        --region $REGION \
        --query 'ScheduleExpression' \
        --output text)
    print_pass "EventBridge schedule is ENABLED ($SCHEDULE_EXPR)"
else
    print_fail "EventBridge schedule state: $SCHEDULE_STATE"
fi

print_test "Testing Lambda Producer invocation"
INVOKE_RESULT=$(aws lambda invoke \
    --function-name "$LAMBDA_PRODUCER" \
    --region $REGION \
    --log-type Tail \
    /tmp/producer-test.json 2>&1)

if echo "$INVOKE_RESULT" | grep -q "StatusCode.*200"; then
    LOGS_SENT=$(cat /tmp/producer-test.json | jq -r '.body' | jq -r '.logs_sent' 2>/dev/null || echo "0")
    print_pass "Producer invocation successful (Logs sent: $LOGS_SENT)"
else
    print_fail "Producer invocation failed"
    echo "$INVOKE_RESULT"
fi

print_test "Checking Producer recent logs"
RECENT_LOGS=$(aws logs filter-log-events \
    --log-group-name "/aws/lambda/$LAMBDA_PRODUCER" \
    --region $REGION \
    --start-time $(($(date +%s) * 1000 - 300000)) \
    --query 'events[?message!=null]|[0].message' \
    --output text 2>/dev/null)

if [ -n "$RECENT_LOGS" ] && [ "$RECENT_LOGS" != "None" ]; then
    print_pass "Producer has recent log entries"
    print_info "Latest: ${RECENT_LOGS:0:100}..."
else
    print_warning "No recent Producer logs found (may not have run yet)"
fi

# Test Lambda Consumer
print_header "STEP 4: Lambda Consumer Function"

print_test "Checking Lambda Consumer existence"
if aws lambda get-function \
    --function-name "$LAMBDA_CONSUMER" \
    --region $REGION &>/dev/null; then
    print_pass "Lambda Consumer exists"
else
    print_fail "Lambda Consumer not found"
fi

print_test "Checking Lambda Consumer configuration"
CONSUMER_STATE=$(aws lambda get-function-configuration \
    --function-name "$LAMBDA_CONSUMER" \
    --region $REGION \
    --query 'State' \
    --output text 2>/dev/null)

CONSUMER_TIMEOUT=$(aws lambda get-function-configuration \
    --function-name "$LAMBDA_CONSUMER" \
    --region $REGION \
    --query 'Timeout' \
    --output text 2>/dev/null)

if [ "$CONSUMER_STATE" == "Active" ]; then
    print_pass "Lambda Consumer is Active (Timeout: ${CONSUMER_TIMEOUT}s)"
else
    print_fail "Lambda Consumer state: $CONSUMER_STATE"
fi

print_test "Checking MSK Event Source Mapping"
EVENT_SOURCE=$(aws lambda list-event-source-mappings \
    --function-name "$LAMBDA_CONSUMER" \
    --region $REGION \
    --query 'EventSourceMappings[0]' 2>/dev/null)

if [ -n "$EVENT_SOURCE" ] && [ "$EVENT_SOURCE" != "null" ]; then
    ESM_STATE=$(echo "$EVENT_SOURCE" | jq -r '.State')
    ESM_BATCH=$(echo "$EVENT_SOURCE" | jq -r '.BatchSize')

    if [ "$ESM_STATE" == "Enabled" ] || [ "$ESM_STATE" == "Enabling" ]; then
        print_pass "Event Source Mapping is $ESM_STATE (Batch size: $ESM_BATCH)"
    else
        print_fail "Event Source Mapping state: $ESM_STATE"
    fi
else
    print_fail "No Event Source Mapping found"
fi

print_test "Checking Consumer recent logs"
CONSUMER_LOGS=$(aws logs filter-log-events \
    --log-group-name "/aws/lambda/$LAMBDA_CONSUMER" \
    --region $REGION \
    --start-time $(($(date +%s) * 1000 - 300000)) \
    --query 'events[?message!=null]|[0].message' \
    --output text 2>/dev/null)

if [ -n "$CONSUMER_LOGS" ] && [ "$CONSUMER_LOGS" != "None" ]; then
    print_pass "Consumer has recent log entries"
    print_info "Latest: ${CONSUMER_LOGS:0:100}..."
else
    print_warning "No recent Consumer logs (may not have received messages yet)"
fi

# Test OpenSearch
print_header "STEP 5: OpenSearch Serverless Collection"

print_test "Checking OpenSearch collection status"
COLLECTION_ID=$(get_terraform_output opensearch_collection_id)
COLLECTION_STATUS=$(aws opensearchserverless batch-get-collection \
    --ids "$COLLECTION_ID" \
    --region $REGION \
    --query 'collectionDetails[0].status' \
    --output text 2>/dev/null)

if [ "$COLLECTION_STATUS" == "ACTIVE" ]; then
    print_pass "OpenSearch collection is ACTIVE"
else
    print_fail "OpenSearch collection status: $COLLECTION_STATUS"
fi

print_test "Checking OpenSearch data (using Python script)"
cat > /tmp/check_opensearch.py << 'PYTHON_EOF'
import boto3
import sys
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

OPENSEARCH_ENDPOINT = sys.argv[1]
INDEX_NAME = "error-logs-mock"
REGION = sys.argv[2]

try:
    credentials = boto3.Session().get_credentials()
    awsauth = AWS4Auth(
        credentials.access_key,
        credentials.secret_key,
        REGION,
        'aoss',
        session_token=credentials.token
    )

    client = OpenSearch(
        hosts=[{'host': OPENSEARCH_ENDPOINT, 'port': 443}],
        http_auth=awsauth,
        use_ssl=True,
        verify_certs=True,
        connection_class=RequestsHttpConnection,
        timeout=30
    )

    if client.indices.exists(index=INDEX_NAME):
        stats = client.indices.stats(index=INDEX_NAME)
        doc_count = stats['_all']['primaries']['docs']['count']
        print(f"SUCCESS|{doc_count}")
    else:
        print("INDEX_NOT_FOUND|0")
except Exception as e:
    print(f"ERROR|{str(e)}")
PYTHON_EOF

OPENSEARCH_RESULT=$(python3 /tmp/check_opensearch.py "$OPENSEARCH_ENDPOINT" "$REGION" 2>/dev/null || echo "ERROR|Script failed")
OPENSEARCH_STATUS=$(echo "$OPENSEARCH_RESULT" | cut -d'|' -f1)
OPENSEARCH_DOCS=$(echo "$OPENSEARCH_RESULT" | cut -d'|' -f2)

if [ "$OPENSEARCH_STATUS" == "SUCCESS" ]; then
    if [ "$OPENSEARCH_DOCS" -gt 0 ]; then
        print_pass "OpenSearch has $OPENSEARCH_DOCS documents indexed"
    else
        print_warning "OpenSearch index exists but has 0 documents (wait 2-3 minutes)"
    fi
elif [ "$OPENSEARCH_STATUS" == "INDEX_NOT_FOUND" ]; then
    print_warning "OpenSearch index not created yet (wait 2-3 minutes for first data)"
else
    print_fail "OpenSearch check failed: $OPENSEARCH_DOCS"
fi

# Test RAG Service
print_header "STEP 6: RAG Service (Kubernetes)"

print_test "Checking RAG service pods"
RAG_PODS=$(kubectl get pods -l app=eks-rag -n default -o json 2>/dev/null | jq -r '.items | length')

if [ "$RAG_PODS" -gt 0 ]; then
    READY_PODS=$(kubectl get pods -l app=eks-rag -n default -o json | jq -r '[.items[] | select(.status.phase=="Running")] | length')
    print_pass "RAG service has $READY_PODS/$RAG_PODS pods running"
else
    print_fail "No RAG service pods found"
fi

print_test "Checking RAG service endpoint"
if kubectl get svc eks-rag-service -n default &>/dev/null; then
    SVC_TYPE=$(kubectl get svc eks-rag-service -n default -o jsonpath='{.spec.type}')
    print_pass "RAG service exists (Type: $SVC_TYPE)"
else
    print_fail "RAG service not found"
fi

# Test UI
print_header "STEP 7: Gradio UI"

print_test "Checking UI pods"
UI_PODS=$(kubectl get pods -l app=gradio-app -n default -o json 2>/dev/null | jq -r '.items | length')

if [ "$UI_PODS" -gt 0 ]; then
    READY_UI=$(kubectl get pods -l app=gradio-app -n default -o json | jq -r '[.items[] | select(.status.phase=="Running")] | length')
    print_pass "UI has $READY_UI/$UI_PODS pods running"
else
    print_fail "No UI pods found"
fi

print_test "Checking UI Ingress/ALB"
if kubectl get ingress gradio-app-ingress -n default &>/dev/null; then
    ALB_HOST=$(kubectl get ingress gradio-app-ingress -n default -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
    if [ -n "$ALB_HOST" ]; then
        print_pass "ALB provisioned: $ALB_HOST"
    else
        print_warning "ALB still provisioning"
    fi
else
    print_fail "UI Ingress not found"
fi

print_test "Testing UI accessibility"
if curl -s -o /dev/null -w "%{http_code}" "$UI_URL" --max-time 10 | grep -q "200\|302"; then
    print_pass "UI is accessible at $UI_URL"
else
    print_warning "UI not responding yet (may still be starting)"
fi

# End-to-End Test
print_header "STEP 8: End-to-End Data Flow"

print_test "Checking complete pipeline health"
PIPELINE_HEALTHY=true

# Check if Producer ran recently
LAST_PRODUCER_RUN=$(aws logs filter-log-events \
    --log-group-name "/aws/lambda/$LAMBDA_PRODUCER" \
    --region $REGION \
    --start-time $(($(date +%s) * 1000 - 300000)) \
    --query 'events[-1].timestamp' \
    --output text 2>/dev/null)

if [ "$LAST_PRODUCER_RUN" != "None" ] && [ -n "$LAST_PRODUCER_RUN" ]; then
    MINUTES_AGO=$(( ($(date +%s) * 1000 - $LAST_PRODUCER_RUN) / 60000 ))
    print_info "Producer last ran $MINUTES_AGO minutes ago"
else
    print_warning "Producer hasn't run yet"
    PIPELINE_HEALTHY=false
fi

# Check if Consumer processed data
LAST_CONSUMER_RUN=$(aws logs filter-log-events \
    --log-group-name "/aws/lambda/$LAMBDA_CONSUMER" \
    --region $REGION \
    --start-time $(($(date +%s) * 1000 - 300000)) \
    --query 'events[-1].timestamp' \
    --output text 2>/dev/null)

if [ "$LAST_CONSUMER_RUN" != "None" ] && [ -n "$LAST_CONSUMER_RUN" ]; then
    MINUTES_AGO=$(( ($(date +%s) * 1000 - $LAST_CONSUMER_RUN) / 60000 ))
    print_info "Consumer last ran $MINUTES_AGO minutes ago"
else
    print_warning "Consumer hasn't run yet"
    PIPELINE_HEALTHY=false
fi

if [ "$PIPELINE_HEALTHY" == "true" ] && [ "$OPENSEARCH_DOCS" -gt 0 ]; then
    print_pass "Complete pipeline is operational!"
    print_info "Data flowing: Producer → MSK → Consumer → OpenSearch ($OPENSEARCH_DOCS docs)"
else
    print_warning "Pipeline is starting up. Wait 2-3 minutes and run again."
fi

# Final Summary
print_header "VALIDATION SUMMARY"

echo "Total Tests: $TESTS_TOTAL"
echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
echo -e "${RED}Failed: $TESTS_FAILED${NC}"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✅ ALL TESTS PASSED!${NC}"
    echo ""
    echo "Next Steps:"
    echo "1. Open UI in browser: $UI_URL"
    echo "2. Try a query: 'Show recent engine temperature alerts'"
    echo "3. Monitor logs:"
    echo "   aws logs tail /aws/lambda/$LAMBDA_PRODUCER --follow --region $REGION"
    echo "   aws logs tail /aws/lambda/$LAMBDA_CONSUMER --follow --region $REGION"
    exit 0
else
    echo -e "${RED}❌ SOME TESTS FAILED${NC}"
    echo ""
    echo "Troubleshooting:"
    echo "1. Check Lambda logs for errors"
    echo "2. Verify IAM permissions"
    echo "3. Check MSK cluster connectivity"
    echo "4. See: eks-rag/terraform/MSK_LAMBDA_DEPLOYMENT.md"
    exit 1
fi
