# Real-Time RAG Pipeline Validation

This directory contains comprehensive validation scripts to verify the entire real-time RAG pipeline deployment.

## Quick Start

```bash
cd eks-rag/testing
./validate-deployment.sh
```

## What It Tests

The validation script performs **8 comprehensive test steps** covering all components:

### Step 1: Prerequisites ✅
- AWS credentials validity
- Terraform state accessibility
- All component ARNs/endpoints

### Step 2: MSK Serverless Cluster ✅
- Cluster status (ACTIVE)
- SASL/IAM authentication enabled
- Cluster ARN and configuration

### Step 3: Lambda Producer Function ✅
- Function existence and configuration
- Runtime and state (Active)
- EventBridge schedule (ENABLED)
- Test invocation (generates 10 logs)
- Recent log entries

### Step 4: Lambda Consumer Function ✅
- Function existence and configuration
- MSK Event Source Mapping (Enabled)
- Batch configuration (100 messages, 10s window)
- Recent processing logs

### Step 5: OpenSearch Serverless ✅
- Collection status (ACTIVE)
- Index existence (`error-logs-mock`)
- Document count (should grow over time)
- Vector embeddings present

### Step 6: RAG Service (Kubernetes) ✅
- Pod status and count
- Service endpoint availability
- ClusterIP configuration

### Step 7: Gradio UI ✅
- Pod status and count
- Ingress/ALB provisioning
- ALB hostname
- HTTP accessibility

### Step 8: End-to-End Data Flow ✅
- Producer recent execution
- Consumer recent execution
- Data in OpenSearch
- Complete pipeline health

## Execution

### Basic Run

```bash
./validate-deployment.sh
```

### With Custom Region

```bash
AWS_REGION=us-east-1 ./validate-deployment.sh
```

### Expected Output

```
========================================
Real-Time RAG Pipeline Validation
========================================

Region: us-west-2
Started: 2025-10-02 10:30:00

========================================
STEP 1: Prerequisites
========================================

[TEST 1] Checking AWS credentials
✅ PASS: AWS credentials valid (Account: 533267377863)

[TEST 2] Checking Terraform outputs
✅ PASS: Terraform state accessible

ℹ️  INFO: MSK Cluster: vehicle-logs-cluster
ℹ️  INFO: Lambda Producer: vehicle-log-producer
ℹ️  INFO: Lambda Consumer: vehicle-log-consumer
...

========================================
VALIDATION SUMMARY
========================================

Total Tests: 24
Passed: 22
Failed: 0

✅ ALL TESTS PASSED!

Next Steps:
1. Open UI in browser: http://gradio-app-ingress-930176546.us-west-2.elb.amazonaws.com
2. Try a query: 'Show recent engine temperature alerts'
3. Monitor logs:
   aws logs tail /aws/lambda/vehicle-log-producer --follow --region us-west-2
   aws logs tail /aws/lambda/vehicle-log-consumer --follow --region us-west-2
```

## Test Results Interpretation

### All Green (PASS) ✅
- System is fully operational
- Data pipeline is flowing correctly
- Ready for production use

### Some Yellow (WARNING) ⚠️
- System is starting up
- Wait 2-3 minutes and re-run
- Common during first 5 minutes after deployment

### Any Red (FAIL) ❌
- Component issue detected
- Check specific error message
- See troubleshooting section below

## Timing Considerations

**First Run After Deployment:**
- Some components may show warnings
- EventBridge runs every 1 minute
- First data may take 2-3 minutes to appear in OpenSearch

**Recommended Wait Time:**
Wait **3-5 minutes** after `terraform apply` before running validation for accurate results.

## Troubleshooting

### Producer Not Running
```bash
# Check EventBridge rule
aws events describe-rule --name vehicle-log-producer-schedule --region us-west-2

# Manual trigger
aws lambda invoke \
  --function-name vehicle-log-producer \
  --region us-west-2 \
  /tmp/test.json
```

### Consumer Not Processing
```bash
# Check event source mapping
aws lambda list-event-source-mappings \
  --function-name vehicle-log-consumer \
  --region us-west-2

# Check Consumer logs
aws logs tail /aws/lambda/vehicle-log-consumer --follow --region us-west-2
```

### No Data in OpenSearch
```bash
# Check Consumer processed messages
aws logs filter-log-events \
  --log-group-name /aws/lambda/vehicle-log-consumer \
  --region us-west-2 \
  --start-time $(($(date +%s) * 1000 - 600000)) \
  --filter-pattern "indexed"

# Manual OpenSearch check
python3 /tmp/check_opensearch_data.py
```

### UI Not Accessible
```bash
# Check Ingress status
kubectl get ingress gradio-app-ingress -n default

# Check ALB provisioning (may take 2-3 minutes)
kubectl describe ingress gradio-app-ingress -n default
```

## Prerequisites

The script requires:
- `aws` CLI configured with valid credentials
- `kubectl` configured for EKS cluster
- `jq` for JSON parsing
- `python3` with `boto3`, `opensearch-py`, `requests-aws4auth`
- Terraform state in `../terraform/`

### Install Prerequisites

```bash
# macOS
brew install jq

# Install Python dependencies
pip3 install boto3 opensearch-py requests-aws4auth

# Verify
which aws && which kubectl && which jq && which python3
```

## Manual Component Testing

### Test Lambda Producer Only

```bash
aws lambda invoke \
  --function-name vehicle-log-producer \
  --region us-west-2 \
  /tmp/producer-test.json

cat /tmp/producer-test.json | jq
```

### Test OpenSearch Only

```bash
python3 << EOF
import boto3
from opensearchpy import OpenSearch, RequestsHttpConnection
from requests_aws4auth import AWS4Auth

endpoint = "$(cd ../terraform && terraform output -raw opensearch_collection_endpoint)"
credentials = boto3.Session().get_credentials()
awsauth = AWS4Auth(credentials.access_key, credentials.secret_key, 'us-west-2', 'aoss', session_token=credentials.token)
client = OpenSearch(hosts=[{'host': endpoint, 'port': 443}], http_auth=awsauth, use_ssl=True, verify_certs=True, connection_class=RequestsHttpConnection)

stats = client.indices.stats(index='error-logs-mock')
print(f"Documents: {stats['_all']['primaries']['docs']['count']}")
EOF
```

### Test RAG Service Only

```bash
kubectl run test-pod --rm -it --image=curlimages/curl --restart=Never -- \
  curl -X POST http://eks-rag-service.default.svc.cluster.local/submit_query \
  -H "Content-Type: application/json" \
  -d '{"query": "Show critical engine temperature alerts"}'
```

## Continuous Monitoring

### Watch Lambda Logs

```bash
# Producer (terminal 1)
aws logs tail /aws/lambda/vehicle-log-producer --follow --region us-west-2

# Consumer (terminal 2)
aws logs tail /aws/lambda/vehicle-log-consumer --follow --region us-west-2
```

### Monitor OpenSearch Growth

```bash
watch -n 30 'python3 /tmp/check_opensearch_data.py'
```

### Monitor MSK Metrics

```bash
# Check cluster metrics (via CloudWatch)
aws cloudwatch get-metric-statistics \
  --namespace AWS/Kafka \
  --metric-name MessagesInPerSec \
  --dimensions Name=Cluster\ Name,Value=vehicle-logs-cluster \
  --start-time $(date -u -d '10 minutes ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 60 \
  --statistics Sum \
  --region us-west-2
```

## Exit Codes

- `0` - All tests passed
- `1` - One or more tests failed

## Log Files

Temporary files created during testing:
- `/tmp/producer-test.json` - Producer invocation result
- `/tmp/check_opensearch.py` - OpenSearch validation script

## Support

For issues:
1. Run validation script with full output
2. Check Lambda CloudWatch logs
3. Verify IAM permissions
4. See main deployment guide: `../terraform/MSK_LAMBDA_DEPLOYMENT.md`

## Advanced Usage

### Test Specific Step Only

Edit the script and comment out other steps:

```bash
# Comment out steps you don't want to run
# print_header "STEP 2: MSK Serverless Cluster"
# ...
```

### JSON Output Mode

For CI/CD integration:

```bash
./validate-deployment.sh 2>&1 | tee validation-results.log
```

### Scheduled Validation

Run every 5 minutes via cron:

```bash
*/5 * * * * /path/to/eks-rag/testing/validate-deployment.sh >> /var/log/rag-validation.log 2>&1
```

## Expected Behavior

**Normal Operation:**
- Producer runs every 1 minute
- Generates 10 logs per run
- Consumer processes batches within seconds
- OpenSearch document count increases by ~10/minute
- RAG queries return fresh data

**First 5 Minutes:**
- Some warnings are normal
- Wait for first EventBridge trigger
- OpenSearch index creation takes time
- Consumer may not have data yet

**After 10 Minutes:**
- All tests should pass
- OpenSearch should have 50-100+ documents
- UI should be fully accessible
- End-to-end flow working

## See Also

- Main deployment guide: `../terraform/MSK_LAMBDA_DEPLOYMENT.md`
- Validation report: `../terraform/MSK_LAMBDA_VALIDATION.md`
- Terraform outputs: Run `cd ../terraform && terraform output`
