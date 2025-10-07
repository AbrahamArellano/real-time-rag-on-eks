# Real-Time RAG with MSK + Lambda Deployment Guide

## Architecture Overview

```
EventBridge (every 1 minute)
    ↓
Lambda Producer (generates IoT vehicle error logs)
    ↓
MSK Serverless (topic: vehicle-error-logs)
    ↓
Lambda Consumer (MSK trigger)
    ↓
Bedrock Cohere (generate 1024-dim embeddings)
    ↓
OpenSearch Serverless (k-NN vector index)
    ↓
RAG Service (query fresh data)
    ↓
Gradio UI (user interface)
```

## What's New

This deployment adds **4 new modules** to enable real-time streaming data ingestion:

1. **lambda-layers**: AWS4Auth, OpenSearch-py, Kafka-python Lambda layers
2. **msk**: MSK Serverless cluster with SASL/IAM authentication
3. **lambda-producer**: EventBridge-triggered function generating vehicle logs
4. **lambda-consumer**: MSK-triggered function indexing to OpenSearch

## Prerequisites

- Existing Terraform deployment (RAG service + UI)
- AWS credentials configured
- Python 3.9+ with pip

## Deployment

### Step 1: Initialize Terraform

```bash
cd eks-rag/terraform
terraform init
```

### Step 2: Review Plan

```bash
terraform plan
```

**Expected new resources**: ~25-30 resources
- MSK Serverless cluster
- 2 Lambda functions
- 3 Lambda layers
- IAM roles and policies
- EventBridge rule
- MSK event source mapping

### Step 3: Deploy

```bash
terraform apply
```

Type `yes` when prompted.

**Deployment time**: ~15-20 minutes
- Lambda layers: 2-3 minutes
- MSK Serverless: 5-7 minutes
- Lambda functions: 2-3 minutes
- Event source mapping: 2-3 minutes
- Existing resources (RAG + UI): 8-12 minutes

### Step 4: Verify Deployment

```bash
# Check outputs
terraform output

# Verify Lambda Producer
aws lambda invoke \
  --function-name vehicle-log-producer \
  --region us-west-2 \
  /tmp/producer-test.json

cat /tmp/producer-test.json

# Check Producer logs
aws logs tail /aws/lambda/vehicle-log-producer --follow --region us-west-2

# Check Consumer logs
aws logs tail /aws/lambda/vehicle-log-consumer --follow --region us-west-2
```

### Step 5: Verify OpenSearch Data

Wait 2-3 minutes for data to flow through the pipeline, then check:

```bash
# Use the existing check script
python3 /tmp/check_opensearch_data.py
```

Expected output:
```
✅ Index 'error-logs-mock' EXISTS
📊 Index Statistics:
  - Total Documents: 30-50 (growing every minute)
  - Index Size: XXX bytes
📄 Sample Documents (latest 5):
  Document 1:
    Message: Engine temperature sensor reading critical...
    Service: vehicle-telemetry
    Error Code: SENSOR_001
```

### Step 6: Test RAG Query

```bash
# Get UI URL
export UI_URL=$(terraform output -raw ui_url)
echo "Open browser: $UI_URL"

# Or test via curl
curl -X POST http://$(terraform output -raw ui_alb_hostname)/submit_query \
  -H "Content-Type: application/json" \
  -d '{"query": "Show recent engine temperature alerts"}'
```

## Monitoring

### Lambda Producer Metrics

```bash
# View invocations
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Invocations \
  --dimensions Name=FunctionName,Value=vehicle-log-producer \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 \
  --statistics Sum \
  --region us-west-2
```

### Lambda Consumer Metrics

```bash
# View event source mapping metrics
aws lambda get-event-source-mapping \
  --uuid $(terraform output -json | jq -r '.lambda_consumer_name.value') \
  --region us-west-2
```

### MSK Topic Status

```bash
# Check MSK cluster
aws kafka describe-cluster-v2 \
  --cluster-arn $(terraform output -raw msk_cluster_arn) \
  --region us-west-2
```

## Data Flow Validation

### End-to-End Test

1. **Producer generates logs** (every minute):
   - EventBridge triggers Lambda
   - Lambda generates 10 vehicle error logs
   - Publishes to MSK topic `vehicle-error-logs`

2. **Consumer indexes data** (real-time):
   - MSK triggers Lambda with batches
   - Lambda calls Bedrock for embeddings
   - Indexes to OpenSearch with k-NN vectors

3. **RAG queries fresh data**:
   - User submits query via UI
   - RAG service searches OpenSearch vectors
   - Returns recent vehicle errors matching query

### Verify Each Stage

```bash
# 1. Check EventBridge rule
aws events describe-rule \
  --name vehicle-log-producer-schedule \
  --region us-west-2

# 2. Check recent Producer invocations
aws lambda list-function-event-invoke-configs \
  --function-name vehicle-log-producer \
  --region us-west-2

# 3. Check MSK event source
aws lambda list-event-source-mappings \
  --function-name vehicle-log-consumer \
  --region us-west-2

# 4. Query OpenSearch document count
# (Use check_opensearch_data.py script)
```

## Troubleshooting

### Producer Not Running

```bash
# Check EventBridge rule is enabled
aws events describe-rule \
  --name vehicle-log-producer-schedule \
  --region us-west-2 | jq '.State'

# Should return: "ENABLED"

# Check Producer logs for errors
aws logs tail /aws/lambda/vehicle-log-producer \
  --since 10m \
  --region us-west-2
```

### Consumer Not Processing Messages

```bash
# Check event source mapping state
aws lambda list-event-source-mappings \
  --function-name vehicle-log-consumer \
  --region us-west-2 | jq '.EventSourceMappings[0].State'

# Should return: "Enabled"

# Check Consumer IAM permissions
aws iam get-role-policy \
  --role-name vehicle-log-consumer-role \
  --policy-name msk-read-access \
  --region us-west-2
```

### No Data in OpenSearch

```bash
# Check Consumer logs
aws logs tail /aws/lambda/vehicle-log-consumer \
  --follow \
  --region us-west-2

# Look for:
# - "Indexed X documents..." (success)
# - "Error generating embedding" (Bedrock issue)
# - "Error indexing document" (OpenSearch issue)
```

### Bedrock Errors

```bash
# Check Bedrock permissions
aws iam get-role-policy \
  --role-name vehicle-log-consumer-role \
  --policy-name bedrock-access \
  --region us-west-2

# Test Bedrock directly
aws bedrock-runtime invoke-model \
  --model-id cohere.embed-english-v3 \
  --region us-west-2 \
  --body '{"texts":["test"],"input_type":"search_document"}' \
  /tmp/bedrock-test.json
```

## Configuration

### Adjust Log Generation Rate

Edit `main.tf`:

```hcl
module "lambda_producer" {
  # ...
  schedule_expression = "rate(30 seconds)"  # Generate logs every 30 seconds
  logs_per_invocation = 20                   # Generate 20 logs per invocation
}
```

Then apply:
```bash
terraform apply
```

### Change Kafka Topic

Edit `main.tf`:

```hcl
topic_name = "my-custom-topic"
```

Then apply:
```bash
terraform apply
```

## Cost Estimation

Monthly costs for new components:

- **MSK Serverless**: ~$50-100 (based on throughput)
- **Lambda Producer**: ~$0.20 (43,200 invocations/month @ 128MB, 5s avg)
- **Lambda Consumer**: ~$5-10 (based on MSK event volume)
- **Bedrock Embeddings**: ~$2-5 (based on 14,400 requests/month)

**Total additional cost**: ~$57-115/month

## Cleanup

To remove MSK and Lambda components only:

```bash
# Remove specific modules
terraform destroy \
  -target=module.lambda_consumer \
  -target=module.lambda_producer \
  -target=module.msk \
  -target=module.lambda_layers
```

To remove everything:

```bash
terraform destroy
```

## Next Steps

1. **Customize Log Schema**: Edit `producer.py` to match your data model
2. **Add Monitoring**: Set up CloudWatch alarms for failures
3. **Scale**: Adjust batch size and concurrency in consumer
4. **Security**: Move to private VPC endpoints for production

## Support

For issues:
1. Check Lambda logs: `/aws/lambda/vehicle-log-producer` and `/aws/lambda/vehicle-log-consumer`
2. Verify IAM permissions
3. Check OpenSearch data access policy includes Lambda role ARN
4. Review Terraform state: `terraform show`
