# Advanced RAG System on EKS - Terraform Deployment

This Terraform configuration provides automated end-to-end deployment of a **real-time RAG (Retrieval-Augmented Generation)** system on Amazon EKS with temporal query filtering, vector search, and LLM integration.

## Table of Contents
- [System Architecture](#system-architecture)
- [Key Features](#key-features)
- [Recent Enhancements](#recent-enhancements)
- [Prerequisites](#prerequisites)
- [Installation Guide](#installation-guide)
- [Usage Examples](#usage-examples)
- [Architecture Components](#architecture-components)
- [Troubleshooting](#troubleshooting)
- [Cost Estimation](#cost-estimation)

---

## System Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           REAL-TIME DATA PIPELINE                            │
└─────────────────────────────────────────────────────────────────────────────┘

  ┌──────────────────┐         ┌──────────────────┐         ┌────────────────┐
  │ Lambda Producer  │────────>│ Kinesis Stream   │────────>│ Lambda Consumer│
  │                  │         │                  │         │                │
  │ • Vehicle Logs   │         │ error-logs-      │         │ • Bedrock      │
  │ • 100 logs/min   │         │ stream           │         │   Embeddings   │
  │ • Current time   │         │                  │         │ • Index to OS  │
  └──────────────────┘         └──────────────────┘         └────────┬───────┘
                                                                      │
                                                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         VECTOR SEARCH & STORAGE                              │
└─────────────────────────────────────────────────────────────────────────────┘

                              ┌────────────────────────────────┐
                              │  OpenSearch Serverless         │
                              │  Collection: error-logs-mock   │
                              │                                │
                              │  • Index: error-logs-mock      │
                              │  • KNN Vectors (1024 dim)      │
                              │  • FAISS HNSW Engine           │
                              │  • Timestamp Field (date)      │
                              │  • Vehicle Telemetry Data      │
                              └────────────────────────────────┘
                                         ▲
                                         │
┌─────────────────────────────────────────────────────────────────────────────┐
│                              RAG QUERY FLOW                                  │
└─────────────────────────────────────────────────────────────────────────────┘

  ┌──────────────┐           ┌────────────────────────────────────────┐
  │  User Query  │──────────>│  Gradio UI (ALB Exposed)               │
  │              │           │  • Web Interface                       │
  │ "Show engine │           │  • Query Input                         │
  │  errors in   │           │  • Results Display                     │
  │  last 1 day" │           └──────────────┬─────────────────────────┘
  └──────────────┘                          │
                                            ▼
                              ┌────────────────────────────────────────┐
                              │  RAG Backend Service (Flask)           │
                              │  vector_search_service.py              │
                              │                                        │
                              │  ┌──────────────────────────────────┐ │
                              │  │ 1. Temporal Query Parser         │ │
                              │  │    • Regex: "last N day/hour"    │ │
                              │  │    • Output: {"gte": "now-1d"}   │ │
                              │  └──────────────────────────────────┘ │
                              │                                        │
                              │  ┌──────────────────────────────────┐ │
                              │  │ 2. Bedrock Embeddings            │ │
                              │  │    • Model: cohere.embed-v3      │ │
      ┌──────────────────────>│  │    • Dimension: 1024             │ │
      │                       │  └──────────────────────────────────┘ │
      │                       │                                        │
      │                       │  ┌──────────────────────────────────┐ │
      │  ┌───────────────────>│  │ 3. Vector Search + Date Filter   │ │
      │  │                    │  │    • KNN similarity search       │ │
      │  │                    │  │    • Bool query with range       │ │
      │  │                    │  │    • Returns: top-k + timestamp  │ │
      │  │                    │  └──────────────────────────────────┘ │
      │  │                    └────────────────────────────────────────┘
      │  │                                     │
      │  │                                     ▼
      │  │                    ┌────────────────────────────────────────┐
      │  │                    │  vLLM on Inferentia2                   │
      │  │                    │  • Model: Llama-3-8B-Instruct          │
      │  └────────────────────│  • System Prompt: Current UTC Time     │
      │                       │  • Context: Search Results + Timestamp │
      └───────────────────────│  • Response: Natural Language Answer   │
                              └────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                           IAM & SECURITY                                     │
└─────────────────────────────────────────────────────────────────────────────┘

  ┌──────────────────────────────────────────────────────────────────────┐
  │  IRSA (IAM Roles for Service Accounts)                               │
  │                                                                       │
  │  ┌─────────────────────┐         ┌───────────────────────────┐      │
  │  │  ServiceAccount      │────────>│  IAM Role                 │      │
  │  │  eks-rag-sa          │         │                           │      │
  │  └─────────────────────┘         │  • Bedrock InvokeModel    │      │
  │                                   │  • OpenSearch AOSS Access │      │
  │                                   │  • OIDC Trust Policy      │      │
  │                                   └───────────────────────────┘      │
  │                                                                       │
  │  OpenSearch Access Policies:                                         │
  │  • EKS IAM Role (RAG Backend)                                        │
  │  • Lambda Consumer Role                                              │
  │  • User ARN (for Console access)                                     │
  └──────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────┐
│                        DEPLOYMENT INFRASTRUCTURE                             │
└─────────────────────────────────────────────────────────────────────────────┘

  ┌─────────────────┐     ┌──────────────────┐     ┌─────────────────────┐
  │  ECR Repository │     │  Kubernetes      │     │  Load Balancer      │
  │                 │     │                  │     │                     │
  │  • RAG Backend  │────>│  • Deployment    │<────│  • ALB (Gradio UI)  │
  │  • Gradio UI    │     │  • Service       │     │  • ClusterIP (RAG)  │
  │  • Multi-arch   │     │  • NetworkPolicy │     └─────────────────────┘
  └─────────────────┘     │  • Ingress       │
                          └──────────────────┘
```

---

## Key Features

### 🚀 Real-Time Data Pipeline
- **Lambda Producer**: Generates 100 vehicle error logs per minute with current timestamps
- **Kinesis Stream**: Buffers real-time telemetry data
- **Lambda Consumer**: Enriches logs with Bedrock embeddings and indexes to OpenSearch
- **Zero Indexing Failures**: Robust error handling with monitoring

### 🔍 Advanced Vector Search
- **Semantic Search**: Cohere embed-english-v3 embeddings (1024 dimensions)
- **FAISS HNSW**: High-performance approximate nearest neighbor search
- **Temporal Filtering**: Filter by "last N hours/days/weeks/months"
- **Hybrid Queries**: Combines vector similarity + date range filters

### 🤖 LLM Integration
- **vLLM on Inferentia2**: Optimized inference with Llama-3-8B-Instruct
- **Context-Aware**: LLM receives current UTC time for relative date calculations
- **RAG Pipeline**: Retrieves relevant context before generation

### 📊 Rich Data Model
- Vehicle telemetry (engine temp, battery, fuel pressure, speed)
- Diagnostic codes (DTC codes, system status, maintenance history)
- Geolocation (latitude, longitude)
- Timestamps (UTC, ISO 8601 format)

### 🛡️ Production-Ready Security
- **IRSA**: IAM roles for service accounts with least-privilege policies
- **Network Policies**: Restricted pod egress
- **Image Scanning**: ECR scan-on-push enabled
- **AWS4Auth**: Secure OpenSearch authentication with credential refresh

---

## Recent Enhancements

### Version 2.0 - Temporal Query Support (January 2025)

#### 1. Timestamp Field Integration
**Problem**: LLM responses included "Date/Time: Not provided" even though timestamps existed in OpenSearch.

**Solution**:
- Added `timestamp` to OpenSearch `_source` fields (`vector_search_service.py:120`)
- Included timestamp in results dictionary (`vector_search_service.py:150`)
- Added timestamp to LLM context (`vector_search_service.py:224`)

**Impact**: LLM can now display exact date/time for each error log.

#### 2. Current DateTime Context
**Problem**: LLM couldn't calculate "last day from now" without knowing current time.

**Solution**:
- Modified `query_vllm()` to inject current UTC time into system prompt
- Format: ISO 8601 with 'Z' suffix (matches document timestamps)
- Code: `vector_search_service.py:177-179`

**Impact**: LLM understands relative time expressions like "yesterday", "last week".

#### 3. Temporal Query Filtering
**Problem**: Queries like "errors in the last day" searched entire dataset, not time-filtered results.

**Solution**:
- **Parser**: `parse_temporal_filter()` extracts "last N hour/day/week/month" using regex
- **Query Builder**: Wraps KNN in bool query with range filter when temporal expression detected
- **Integration**: Automatic parsing in `submit_query()` endpoint
- **OpenSearch Date Math**: Uses native `now-Nd` format for efficient filtering

**Supported Patterns**:
```
"last 1 hour"   → {"gte": "now-1h"}
"last 2 days"   → {"gte": "now-2d"}
"last 3 weeks"  → {"gte": "now-3w"}
"last 6 months" → {"gte": "now-6M"}
```

**Impact**:
- Reduces search space (faster queries)
- More relevant results (time-constrained)
- Accurate temporal analysis

**Code Changes**:
- `parse_temporal_filter()`: Lines 95-139
- `vector_search()` modified: Lines 163-234
- Integration in `submit_query()`: Lines 304-309

#### 4. OpenSearch Index Creation Fix
**Problem**: Python script with AWS4Auth authentication failing (404 errors).

**Solution**:
- Replaced Python script with `awscurl` bash implementation
- Added 5-minute `time_sleep` for policy propagation
- Proper dependency tracking via `data_access_policy_id`

**Files Modified**:
- `modules/opensearch-index/main.tf`
- `modules/opensearch/outputs.tf`
- Root `main.tf`

**Impact**: Reliable index creation with knn_vector mapping.

---

## Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.5.0 | Infrastructure as Code |
| AWS CLI | >= 2.x | AWS authentication and testing |
| kubectl | >= 1.28 | Kubernetes resource management |
| Docker | >= 24.x | Container image builds |
| Python | >= 3.9 | Lambda functions and scripts |
| awscurl | Latest | OpenSearch authentication (auto-installed) |
| pipx | Latest | Python tool isolation (recommended) |

**macOS Note**: Docker must support `--platform linux/amd64` for EKS AMD64 nodes.

### Required AWS Resources

#### EKS Cluster
- **Name**: `trainium-inferentia` (configurable)
- **Version**: >= 1.28
- **OIDC Provider**: Enabled (for IRSA)

#### vLLM Service (Prerequisites)
```bash
# Verify vLLM is running
kubectl get svc -n vllm vllm-llama3-inf2-serve-svc

# Expected output:
# NAME                           TYPE        CLUSTER-IP     PORT(S)
# vllm-llama3-inf2-serve-svc    ClusterIP   10.100.x.x     8000/TCP
```

#### AWS Load Balancer Controller
```bash
# Verify installed
kubectl get deployment -n kube-system aws-load-balancer-controller
```

If not installed:
```bash
# Install via Helm
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=trainium-inferentia
```

### Required AWS Permissions

Your AWS credentials need:

**IAM**:
- `iam:CreateRole`
- `iam:CreatePolicy`
- `iam:AttachRolePolicy`
- `iam:GetRole`
- `iam:PassRole`

**OpenSearch Serverless**:
- `aoss:CreateCollection`
- `aoss:CreateSecurityPolicy`
- `aoss:CreateAccessPolicy`
- `aoss:UpdateAccessPolicy`
- `aoss:BatchGetCollection`

**ECR**:
- `ecr:CreateRepository`
- `ecr:PutImage`
- `ecr:InitiateLayerUpload`
- `ecr:GetAuthorizationToken`

**EKS**:
- `eks:DescribeCluster`

**Kinesis**:
- `kinesis:CreateStream`
- `kinesis:DescribeStream`

**Lambda**:
- `lambda:CreateFunction`
- `lambda:UpdateFunctionCode`
- `lambda:InvokeFunction`

**Bedrock**:
- `bedrock:InvokeModel` (for Cohere embeddings)

### Kubernetes Permissions

Your kubectl context needs:
- Create/update resources in `default` namespace
- Read services in `vllm` namespace
- Manage Ingress resources

---

## Installation Guide

### Step 1: Verify Prerequisites

```bash
# 1. Check AWS CLI configuration
aws sts get-caller-identity
# Expected: Your AWS account ID and ARN

# 2. Verify EKS cluster access
kubectl config current-context
kubectl get nodes
# Expected: List of EKS nodes

# 3. Verify vLLM service
kubectl get svc -n vllm vllm-llama3-inf2-serve-svc
# Expected: ClusterIP service on port 8000

# 4. Verify Docker
docker ps
# Expected: Docker daemon running

# 5. Verify AWS Load Balancer Controller
kubectl get deployment -n kube-system aws-load-balancer-controller
# Expected: Deployment running

# 6. Check Bedrock access
aws bedrock list-foundation-models --region us-west-2 --query 'modelSummaries[?contains(modelId, `cohere.embed`)].modelId'
# Expected: cohere.embed-english-v3
```

### Step 2: Clone and Configure

```bash
# Navigate to terraform directory
cd eks-rag/terraform

# Copy example variables (optional - defaults work)
cp terraform.tfvars.example terraform.tfvars

# Edit if needed
vim terraform.tfvars
```

**Key Variables** (`terraform.tfvars`):
```hcl
# AWS Configuration
aws_region      = "us-west-2"
cluster_name    = "trainium-inferentia"

# OpenSearch Configuration
collection_name          = "error-logs-mock"
allow_public_opensearch  = true  # Set false for production

# Kubernetes Configuration
namespace            = "default"
service_account_name = "eks-rag-sa"
vllm_namespace       = "vllm"
vllm_service_name    = "vllm-llama3-inf2-serve-svc"
vllm_port            = 8000

# Application Configuration
replicas             = 2
ecr_repository_name  = "eks-rag"
docker_build_context = "../"
```

### Step 3: Initialize Terraform

```bash
terraform init
```

**Expected Output**:
```
Initializing modules...
- ecr in modules/ecr
- iam in modules/iam
- kinesis in modules/kinesis
- kubernetes in modules/kubernetes
- lambda_consumer in modules/lambda-consumer
- lambda_layers in modules/lambda-layers
- lambda_producer in modules/lambda-producer
- opensearch in modules/opensearch
- opensearch_index in modules/opensearch-index
- ui in modules/ui

Initializing the backend...
Initializing provider plugins...
- terraform.io/builtin/terraform
- hashicorp/aws ~> 5.0
- hashicorp/kubernetes ~> 2.23
- hashicorp/null ~> 3.2
- hashicorp/time ~> 0.9

Terraform has been successfully initialized!
```

### Step 4: Review Plan

```bash
terraform plan
```

**Expected Resource Count**: ~44 resources

**Key Resources to Review**:
- 2 ECR repositories (RAG backend + UI)
- 1 OpenSearch Serverless collection
- 3 OpenSearch policies (encryption, network, data access)
- 1 IAM role + 2 policies (IRSA)
- 1 Kinesis stream
- 3 Lambda functions (producer, consumer, index creation)
- 6 Kubernetes resources (ServiceAccount, Deployment, Service, Ingress, NetworkPolicy)

### Step 5: Deploy

```bash
terraform apply
```

Type `yes` when prompted.

**Deployment Timeline**:
```
[0-2 min]   Creating ECR repositories
[2-7 min]   Building and pushing RAG backend Docker image
[7-10 min]  Building and pushing Gradio UI Docker image
[10-12 min] Creating IAM roles and policies
[12-22 min] Creating OpenSearch Serverless collection
[22-27 min] Waiting for data access policy propagation (5 min)
[27-28 min] Creating OpenSearch index with knn_vector mapping
[28-30 min] Creating Lambda functions and Kinesis stream
[30-32 min] Deploying Kubernetes resources
[32-35 min] Provisioning ALB for Gradio UI

Total: ~35 minutes
```

**Progress Indicators**:
```
✅ module.ecr.aws_ecr_repository.main: Creation complete
✅ null_resource.docker_build_push: Creation complete
✅ module.iam.aws_iam_role.irsa: Creation complete
✅ module.opensearch.aws_opensearchserverless_collection.main: Creation complete
✅ time_sleep.wait_for_policy_propagation: Creation complete
✅ module.opensearch_index.null_resource.create_index: Creation complete
✅ module.lambda_producer.aws_lambda_function.producer: Creation complete
✅ module.kubernetes.kubernetes_deployment.eks_rag: Creation complete
✅ module.ui.kubernetes_ingress_v1.gradio_app: Creation complete

Apply complete! Resources: 44 added, 0 changed, 0 destroyed.
```

### Step 6: Verify Deployment

```bash
# 1. Check Terraform outputs
terraform output

# 2. Verify RAG backend pods
kubectl get pods -l app=eks-rag
# Expected: 2 pods in Running status

# 3. Verify Gradio UI pods
kubectl get pods -l app=gradio-app
# Expected: 1 pod in Running status

# 4. Check Ingress (ALB takes 2-3 minutes to provision)
kubectl get ingress gradio-app-ingress
# Wait for ADDRESS field to show ALB hostname

# 5. Verify Lambda producer is running
aws lambda list-functions --query 'Functions[?contains(FunctionName, `vehicle-log-producer`)].FunctionName'

# 6. Check Kinesis stream
aws kinesis describe-stream --stream-name error-logs-stream --query 'StreamDescription.StreamStatus'
# Expected: ACTIVE

# 7. Verify Lambda consumer is processing
aws logs tail /aws/lambda/vehicle-log-consumer --follow
# Look for: "Completed: X processed, X indexed, 0 failed"

# 8. Test OpenSearch index
terraform output opensearch_collection_endpoint
awscurl --service aoss --region us-west-2 \
  -X GET "https://$(terraform output -raw opensearch_collection_endpoint)/error-logs-mock/_count"
# Expected: {"count": <number>}
```

### Step 7: Access the Application

```bash
# Get UI URL
export UI_URL=$(terraform output -raw ui_url)
echo "🌐 Access the Gradio UI at: $UI_URL"

# Or directly
terraform output ui_url
```

**Open in browser** and test with example queries:
- "Show me critical engine temperature alerts"
- "What battery issues occurred in the last 2 days?"
- "Show vehicles with engine temperature above 110°C in the last day, provide date/time"

---

## Usage Examples

### Example 1: Basic Semantic Search

**Query**: "Show critical engine temperature alerts"

**System Behavior**:
1. No temporal expression detected → semantic-only search
2. Generates embedding via Bedrock (Cohere embed-v3)
3. KNN search in OpenSearch (top 5 results)
4. Returns documents with highest similarity scores
5. LLM generates response with context

**Sample Response**:
```
Critical Engine Temperature Alerts:

1. Vehicle VIN-2341 (2025-01-04T15:23:12Z)
   - Error: Engine temperature critical (125°C)
   - Status: CRITICAL
   - Sensor Readings: engine_temp: 125.4°C, battery: 12.1V

2. Vehicle VIN-1892 (2025-01-04T14:45:08Z)
   - Error: Coolant system failure
   - Status: WARNING
   - Sensor Readings: engine_temp: 118.2°C, battery: 11.8V
```

### Example 2: Temporal Query with Date Filtering

**Query**: "Show battery issues in the last 2 hours"

**System Behavior**:
1. Temporal parser extracts: `{"gte": "now-2h"}`
2. Logs: `"Detected temporal filter: {'gte': 'now-2h'}"`
3. OpenSearch query with bool + filter:
   ```json
   {
     "query": {
       "bool": {
         "must": {"knn": {"message_embedding": {...}}},
         "filter": {"range": {"timestamp": {"gte": "now-2h"}}}
       }
     }
   }
   ```
4. Returns only documents from last 2 hours
5. LLM receives context with timestamps

**Sample Response**:
```
Battery Issues in Last 2 Hours:

1. 2025-01-04T16:45:30Z - Vehicle VIN-4523
   - Low battery voltage: 9.2V (critical threshold)
   - Location: 37.7749°N, -122.4194°W

2. 2025-01-04T16:12:15Z - Vehicle VIN-3341
   - Battery charging failure
   - Voltage: 10.1V, State: IDLE
```

### Example 3: Complex Query

**Query**: "What were the top 3 engine failures last week with exact timestamps?"

**System Behavior**:
1. Parser: `{"gte": "now-1w"}`
2. Semantic: "engine failures" → embedding
3. Filter: timestamp >= 7 days ago
4. Returns: Top 3 by similarity within time window
5. LLM formats with timestamps

### Example 4: Direct API Call

```bash
# From within cluster
kubectl run test-pod --rm -it --image=curlimages/curl --restart=Never -- \
  curl -X POST http://eks-rag-service:5000/submit_query \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Show vehicles with fuel pressure issues in the last day"
  }'

# Expected response structure:
{
  "query": "Show vehicles with fuel pressure issues in the last day",
  "llm_response": "...",
  "similar_documents": [
    {
      "score": 0.87,
      "timestamp": "2025-01-04T14:32:10Z",
      "message": "Fuel pressure sensor malfunction",
      "vehicle_id": "VIN-2341",
      ...
    }
  ],
  "processing_time": 1.23
}
```

### Example 5: Monitoring Real-Time Indexing

```bash
# Watch Lambda consumer logs
aws logs tail /aws/lambda/vehicle-log-consumer --follow

# Expected output (every minute):
[INFO] Processing 100 records from Kinesis
[INFO] Generated 100 embeddings via Bedrock
[INFO] Bulk indexing to OpenSearch...
[INFO] ✅ Completed: 100 processed, 100 indexed, 0 failed

# Check index document count
awscurl --service aoss --region us-west-2 \
  -X GET "https://$(terraform output -raw opensearch_collection_endpoint)/error-logs-mock/_count"

# Document count increases by ~100 every minute
```

---

## Architecture Components

### Module 1: ECR Repositories
**Purpose**: Container image storage for RAG backend and Gradio UI

**Resources**:
- `aws_ecr_repository.main` (RAG backend)
- `aws_ecr_repository.ui` (Gradio UI)
- Lifecycle policy (keep latest 10 images)
- Image scanning on push

**Build Process**:
```bash
# Handled by null_resource.docker_build_push
1. ECR authentication
2. Multi-platform build (linux/amd64)
3. Tag with :latest
4. Push to ECR
5. Trigger rebuild on source changes
```

### Module 2: IAM (IRSA)
**Purpose**: Secure AWS service access from Kubernetes pods

**Resources**:
- IAM role with OIDC trust policy
- Bedrock policy (InvokeModel)
- OpenSearch policy (AOSS access)

**Trust Relationship**:
```json
{
  "Effect": "Allow",
  "Principal": {
    "Federated": "arn:aws:iam::ACCOUNT:oidc-provider/oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID"
  },
  "Action": "sts:AssumeRoleWithWebIdentity",
  "Condition": {
    "StringEquals": {
      "oidc.eks.REGION.amazonaws.com/id/CLUSTER_ID:sub": "system:serviceaccount:default:eks-rag-sa"
    }
  }
}
```

### Module 3: OpenSearch Serverless
**Purpose**: Vector database for semantic search

**Collection Configuration**:
- **Type**: VECTORSEARCH
- **Name**: error-logs-mock
- **Encryption**: AWS-owned keys
- **Network**: Public access (configurable to VPC)

**Index Schema**:
```json
{
  "mappings": {
    "properties": {
      "timestamp": {"type": "date"},
      "message": {"type": "text"},
      "message_embedding": {
        "type": "knn_vector",
        "dimension": 1024,
        "method": {
          "engine": "faiss",
          "name": "hnsw"
        }
      },
      "vehicle_id": {"type": "keyword"},
      "sensor_readings": {
        "properties": {
          "engine_temp": {"type": "float"},
          "battery_voltage": {"type": "float"},
          "fuel_pressure": {"type": "float"},
          "speed": {"type": "float"}
        }
      },
      "location": {
        "properties": {
          "latitude": {"type": "float"},
          "longitude": {"type": "float"}
        }
      }
    }
  },
  "settings": {
    "index": {"knn": true}
  }
}
```

**Access Policy** (Updated via null_resource):
- EKS IRSA role
- Lambda consumer role
- User ARN (for Console access)

### Module 4: Kubernetes Resources
**Purpose**: Deploy RAG backend and UI on EKS

**Resources**:
1. **ServiceAccount**: Annotated with IAM role ARN (IRSA)
2. **Deployment** (RAG Backend):
   - 2 replicas
   - Health checks: liveness + readiness
   - Environment: VLLM_HOST, OPENSEARCH_ENDPOINT
3. **Service** (ClusterIP): Internal endpoint for UI
4. **Deployment** (Gradio UI):
   - 1 replica
   - Connects to `eks-rag-service:5000`
5. **Ingress**: ALB with health checks
6. **NetworkPolicy**: Egress to vLLM + AWS services

### Module 5: Lambda Layers
**Purpose**: Shared dependencies for Lambda functions

**Layers**:
- `aws4auth_layer`: requests-aws4auth for OpenSearch auth
- `opensearch_layer`: opensearch-py client

### Module 6: Kinesis Data Stream
**Purpose**: Buffer for real-time vehicle logs

**Configuration**:
- Stream name: `error-logs-stream`
- Shard count: 1 (auto-scaling enabled)
- Retention: 24 hours

### Module 7: OpenSearch Index Creation
**Purpose**: Create index with knn_vector mapping

**Process**:
1. Wait 5 minutes for policy propagation (`time_sleep`)
2. Install `awscurl` if not present
3. Test endpoint connectivity
4. Check if index exists
5. Create index with full mapping using awscurl

**Key Fix**: Replaced Python AWS4Auth with awscurl for reliable authentication.

### Module 8: Lambda Producer
**Purpose**: Generate mock vehicle error logs

**Configuration**:
- Schedule: Every 1 minute (CloudWatch Events)
- Logs per invocation: 100
- Timestamp: Current UTC time (`datetime.utcnow()`)
- Output: Kinesis stream

**Sample Log**:
```json
{
  "timestamp": "2025-01-04T16:45:30Z",
  "level": "ERROR",
  "service": "ENGINE_CONTROL",
  "error_code": "ENG_TEMP_CRITICAL",
  "message": "Engine temperature exceeds safe operating limits",
  "vehicle_id": "VIN-2341",
  "vehicle_state": "DRIVING",
  "location": {"latitude": 37.7749, "longitude": -122.4194},
  "sensor_readings": {
    "engine_temp": 125.4,
    "battery_voltage": 12.1,
    "fuel_pressure": 45.2,
    "speed": 65.3
  },
  "diagnostic_info": {
    "dtc_codes": ["P0217", "P0218"],
    "system_status": "CRITICAL",
    "last_maintenance": "2024-11-15T08:00:00Z"
  },
  "metadata": {
    "environment": "production",
    "region": "us-west-2",
    "firmware_version": "2.4.1"
  }
}
```

### Module 9: Lambda Consumer
**Purpose**: Process Kinesis records → Bedrock embeddings → OpenSearch

**Process**:
1. Receive batch from Kinesis (up to 100 records)
2. Extract log messages
3. Generate embeddings via Bedrock (Cohere embed-v3)
4. Add `message_embedding` field to each document
5. Bulk index to OpenSearch
6. Log success/failure metrics

**Monitoring**:
```bash
aws logs tail /aws/lambda/vehicle-log-consumer --follow
# Output: "Completed: 100 processed, 100 indexed, 0 failed"
```

### Module 10: Gradio UI
**Purpose**: Web interface for RAG queries

**Features**:
- Example queries
- Real-time response streaming
- Display of similar documents
- Processing time metrics

**Endpoint**: Exposed via ALB Ingress

---

## Troubleshooting

### Issue 1: Pods in ImagePullBackOff

**Symptoms**:
```bash
kubectl get pods -l app=eks-rag
# NAME                       READY   STATUS             RESTARTS
# eks-rag-5b4c7d8f9-xyz12   0/1     ImagePullBackOff   0
```

**Diagnosis**:
```bash
kubectl describe pod -l app=eks-rag | grep -A5 "Events:"
# Error: image architecture mismatch (ARM64 vs AMD64)
```

**Root Cause**: Image built on macOS ARM64 without platform flag.

**Solution**:
```bash
# Taint and rebuild with correct platform
terraform taint null_resource.docker_build_push
terraform apply -target=null_resource.docker_build_push -auto-approve

# Delete failed pods
kubectl delete pods -l app=eks-rag

# Wait for new pods
kubectl wait --for=condition=ready pod -l app=eks-rag --timeout=300s
```

**Prevention**: Build script automatically includes `--platform linux/amd64`.

### Issue 2: OpenSearch Index Creation Timeout

**Symptoms**:
```
Error: local-exec provisioner error
Error creating OpenSearch index: Failed to connect after 20 retries
```

**Diagnosis**:
```bash
# Check collection status
aws opensearchserverless batch-get-collection \
  --ids $(terraform output -raw opensearch_collection_id) \
  --region us-west-2 \
  --query 'collectionDetails[0].status'

# Check data access policy
aws opensearchserverless get-access-policy \
  --name error-logs-mock-access \
  --type data \
  --region us-west-2
```

**Common Causes**:
1. Collection not ACTIVE yet (wait 5-10 minutes)
2. Data access policy missing/not propagated
3. Network policy blocking public access

**Solution**:
```bash
# If collection ACTIVE but policy missing, refresh state
terraform refresh

# Re-apply to create policy
terraform apply -target=module.opensearch

# Wait for propagation (5 minutes is automatic via time_sleep)

# Retry index creation
terraform apply -target=module.opensearch_index
```

### Issue 3: Lambda Consumer Indexing Failures

**Symptoms**:
```bash
aws logs tail /aws/lambda/vehicle-log-consumer --follow
# Output: "Completed: 100 processed, 0 indexed, 100 failed"
```

**Diagnosis**:
```bash
# Check detailed error logs
aws logs tail /aws/lambda/vehicle-log-consumer --filter-pattern "ERROR" --follow

# Common errors:
# - "403 Forbidden" → IAM role not in access policy
# - "404 Not Found" → Index doesn't exist or endpoint wrong
# - "Connection timeout" → Network policy issue
```

**Solution for 403 Forbidden**:
```bash
# Verify Lambda role is in access policy
terraform output -raw opensearch_collection_name
aws opensearchserverless get-access-policy \
  --name error-logs-mock-access \
  --type data \
  --region us-west-2 \
  --query 'accessPolicyDetail.policy' \
  --output text | jq '.[] | .Principal'

# If Lambda role missing, re-run null_resource
terraform taint null_resource.update_opensearch_policy
terraform apply -target=null_resource.update_opensearch_policy
```

### Issue 4: vLLM Connection Refused

**Symptoms**:
```bash
kubectl logs -l app=eks-rag --tail=50
# Error: Failed to connect to vLLM: Connection refused
```

**Diagnosis**:
```bash
# Check vLLM service exists
kubectl get svc -n vllm vllm-llama3-inf2-serve-svc

# Test from RAG pod
kubectl exec -it deployment/eks-rag -- \
  curl -v http://vllm-llama3-inf2-serve-svc.vllm.svc.cluster.local:8000/health
```

**Common Causes**:
1. vLLM service not running
2. NetworkPolicy blocking egress to vllm namespace
3. Service name/port mismatch

**Solution**:
```bash
# Verify NetworkPolicy allows vLLM
kubectl get networkpolicy eks-rag-egress -o yaml | grep -A10 "egress:"

# Should show:
# - to:
#   - namespaceSelector:
#       matchLabels:
#         kubernetes.io/metadata.name: vllm

# If missing, update kubernetes module and re-apply
terraform apply -target=module.kubernetes
```

### Issue 5: ALB Not Provisioning

**Symptoms**:
```bash
kubectl get ingress gradio-app-ingress
# ADDRESS field empty after 5+ minutes
```

**Diagnosis**:
```bash
# Check AWS Load Balancer Controller
kubectl get deployment -n kube-system aws-load-balancer-controller

# Check controller logs
kubectl logs -n kube-system deployment/aws-load-balancer-controller --tail=50

# Check Ingress events
kubectl describe ingress gradio-app-ingress
```

**Common Causes**:
1. AWS Load Balancer Controller not installed
2. Controller lacks IAM permissions
3. Subnets not tagged for ALB discovery

**Solution**:
```bash
# Install controller if missing
helm repo add eks https://aws.github.io/eks-charts
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=trainium-inferentia \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller

# Verify subnets tagged
aws ec2 describe-subnets \
  --filters "Name=tag:kubernetes.io/cluster/trainium-inferentia,Values=shared" \
  --query 'Subnets[].Tags[?Key==`kubernetes.io/role/elb`]'
```

### Issue 6: Temporal Query Not Working

**Symptoms**:
- Query "last 1 day" returns all documents (not filtered by date)
- Logs show: "No temporal filter detected"

**Diagnosis**:
```bash
# Check RAG backend logs
kubectl logs -l app=eks-rag --tail=100 | grep -i "temporal"

# Test temporal parser
kubectl exec -it deployment/eks-rag -- python3 -c "
import re
query = 'show errors in the last 2 days'
pattern = r'\blast\s+(\d+)\s+(hour|day|week|month)s?\b'
match = re.search(pattern, query.lower())
print(f'Match: {match.groups() if match else None}')
"
```

**Common Causes**:
1. Query doesn't match regex pattern (e.g., "past day" instead of "last day")
2. Code changes not deployed
3. Pod running old image

**Solution**:
```bash
# Rebuild and redeploy
terraform taint null_resource.docker_build_push
terraform apply -auto-approve

# Delete old pods
kubectl delete pods -l app=eks-rag

# Verify new image
kubectl get pods -l app=eks-rag -o jsonpath='{.items[0].spec.containers[0].image}'
```

### Issue 7: Docker Build Hanging

**Symptoms**:
```
null_resource.docker_build_push: Still creating... [5m0s elapsed]
# Stuck indefinitely
```

**Diagnosis**:
```bash
# Check Docker daemon
docker ps

# Check disk space
df -h

# Check Docker logs
tail -f ~/Library/Containers/com.docker.docker/Data/log/host/*.log
```

**Solution**:
```bash
# Kill hung processes
pkill -9 terraform
pkill -9 -f "build-and-push"

# Restart Docker
killall Docker && open -a Docker

# Clean up Docker resources
docker system prune -af --volumes

# Retry
terraform apply
```

---

## Cost Estimation

### Monthly Costs (us-west-2)

| Service | Configuration | Estimated Cost |
|---------|--------------|----------------|
| **OpenSearch Serverless** | ~2 OCUs (1 indexing, 1 search) | $140-180 |
| **Kinesis Data Stream** | 1 shard, 24h retention | $15 |
| **Lambda (Producer)** | 43,200 invocations/month (1/min) | $0.50 |
| **Lambda (Consumer)** | 100 records/batch, 43,200 invocations | $2 |
| **Lambda (Index Creation)** | 1 invocation | $0 |
| **Application Load Balancer** | 1 ALB, low traffic | $18 |
| **ECR Storage** | 2 repositories, ~2 GB | $0.20 |
| **EKS** | Using existing cluster | $0 |
| **Bedrock (Embeddings)** | ~4.3M tokens/month (100 logs/min × 60 chars) | $8-12 |
| **Bedrock (Inference)** | Varies by query volume | $5-20 |
| **Data Transfer** | Minimal (in-region) | $1-5 |

**Total**: ~$190-250/month

### Cost Optimization Tips

1. **Reduce Lambda Frequency**: Change producer from `rate(1 minute)` to `rate(5 minutes)` → -80% Lambda costs
2. **Use Provisioned Concurrency**: For predictable workloads → -50% Bedrock latency
3. **OpenSearch Indexing OCU**: Stop indexing OCU after initial load → -$70/month
4. **Private OpenSearch**: Remove public access (requires VPC endpoints) → +$7/month for endpoints
5. **ECR Lifecycle**: Keep only latest 5 images → -50% ECR costs

---

## Security Best Practices

### Production Hardening Checklist

- [ ] **Private OpenSearch**: Set `allow_public_opensearch = false` and configure VPC endpoints
- [ ] **Secrets Management**: Move sensitive values to AWS Secrets Manager
- [ ] **Network Policies**: Restrict egress to specific CIDR ranges
- [ ] **Image Scanning**: Review ECR scan results before deployment
- [ ] **IAM Policies**: Audit and minimize permissions (least privilege)
- [ ] **Encryption**: Enable customer-managed KMS keys for OpenSearch
- [ ] **Monitoring**: Add CloudWatch dashboards and alarms
- [ ] **Backup**: Configure OpenSearch snapshot repository
- [ ] **Authentication**: Add Cognito/OIDC for Gradio UI
- [ ] **Rate Limiting**: Add API Gateway in front of ALB
- [ ] **DDoS Protection**: Enable AWS Shield Standard (free)
- [ ] **VPC Flow Logs**: Enable for network traffic analysis
- [ ] **Cost Alerts**: Set up billing alarms in CloudWatch

### Current Security Posture

**✅ Implemented**:
- IRSA with scoped IAM policies
- ECR image scanning on push
- Network policies for pod egress
- AWS4Auth with credential refresh for OpenSearch
- TLS encryption in transit (ALB → pods)
- Encryption at rest (OpenSearch, ECR)

**⚠️ Needs Improvement for Production**:
- OpenSearch public access enabled
- No authentication on Gradio UI
- Secrets in environment variables (not Secrets Manager)
- No rate limiting or WAF

---

## Updating the Deployment

### Update Application Code

```bash
# Edit vector_search_service.py or other source files
vim ../vector_search_service.py

# Terraform auto-detects changes and rebuilds
terraform apply

# Alternatively, force rebuild
terraform taint null_resource.docker_build_push
terraform apply
```

### Update Terraform Configuration

```bash
# Edit variables
vim terraform.tfvars

# Or edit module configuration
vim main.tf

# Apply changes
terraform plan
terraform apply
```

### Update Lambda Functions

```bash
# Lambda code is in modules/lambda-*/lambda_code/
vim modules/lambda-producer/lambda_code/producer.py

# Apply to update function code
terraform apply -target=module.lambda_producer
```

### Scale Replicas

```bash
# Edit terraform.tfvars
replicas = 3

# Apply
terraform apply -target=module.kubernetes.kubernetes_deployment.eks_rag
```

---

## Cleanup

### Full Destruction

```bash
# Destroy all resources
terraform destroy

# Type 'yes' when prompted
```

**Destruction Order**:
1. Kubernetes resources (Ingress, Deployment, Service)
2. ALB deletion (2-3 minutes)
3. Lambda functions
4. Kinesis stream
5. OpenSearch collection (5-10 minutes)
6. IAM roles and policies
7. ECR repositories (images deleted)

**Total time**: ~15-20 minutes

### Partial Cleanup

```bash
# Destroy only UI
terraform destroy -target=module.ui

# Destroy only Lambda pipeline
terraform destroy -target=module.lambda_producer -target=module.lambda_consumer -target=module.kinesis

# Keep OpenSearch but destroy Kubernetes resources
terraform destroy -target=module.kubernetes -target=module.ui
```

### Troubleshooting Destroy Failures

**Issue**: OpenSearch collection stuck in DELETING
```bash
# Wait for AWS to complete deletion (up to 10 minutes)
aws opensearchserverless batch-get-collection \
  --ids $(terraform output -raw opensearch_collection_id) \
  --region us-west-2
```

**Issue**: ALB not deleting
```bash
# Check for stale target groups
aws elbv2 describe-target-groups \
  --query 'TargetGroups[?contains(TargetGroupName, `k8s`)].TargetGroupArn'

# Manually delete if needed
aws elbv2 delete-target-group --target-group-arn <ARN>
```

---

## Directory Structure

```
eks-rag/terraform/
├── main.tf                          # Root orchestration (11 modules)
├── variables.tf                     # Input variable definitions
├── outputs.tf                       # Output values (endpoints, ARNs)
├── providers.tf                     # AWS, Kubernetes, Null providers
├── versions.tf                      # Terraform version constraints
├── terraform.tfvars.example         # Example variable values
├── README.md                        # This file
│
├── modules/
│   ├── ecr/                        # ECR repository for RAG backend
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── ecr-ui/                     # ECR repository for Gradio UI
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── iam/                        # IRSA role and policies
│   │   ├── main.tf                 # IAM role, Bedrock policy, OpenSearch policy
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── opensearch/                 # OpenSearch Serverless collection
│   │   ├── main.tf                 # Collection, policies (encryption, network, data)
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── opensearch-index/           # Index creation with knn_vector
│   │   ├── main.tf                 # awscurl-based index creation
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── kubernetes/                 # RAG backend Kubernetes resources
│   │   ├── main.tf                 # ServiceAccount, Deployment, Service, NetworkPolicy
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── ui/                         # Gradio UI Kubernetes resources
│   │   ├── main.tf                 # Deployment, Service, Ingress (ALB)
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── kinesis/                    # Kinesis Data Stream
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── lambda-layers/              # Lambda layers (aws4auth, opensearch-py)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   └── outputs.tf
│   │
│   ├── lambda-producer/            # Lambda function (generates logs)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── lambda_code/
│   │       └── producer.py         # Vehicle log generator
│   │
│   └── lambda-consumer/            # Lambda function (Kinesis → OpenSearch)
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       └── lambda_code/
│           └── consumer.py         # Bedrock embeddings + indexing
│
├── scripts/
│   ├── build-and-push.sh           # Docker build and ECR push (RAG backend)
│   └── build-and-push-ui.sh        # Docker build and ECR push (Gradio UI)
│
└── ../                             # Parent directory
    ├── vector_search_service.py    # RAG backend Flask API
    ├── Dockerfile                  # RAG backend container
    ├── requirements.txt            # Python dependencies
    │
    └── ui/
        ├── app.py                  # Gradio UI application
        ├── Dockerfile              # Gradio UI container
        └── requirements.txt        # UI dependencies
```

---

## Support

### Getting Help

1. **Check pod logs**:
   ```bash
   kubectl logs -l app=eks-rag --tail=100 --follow
   kubectl logs -l app=gradio-app --tail=100 --follow
   ```

2. **Check Lambda logs**:
   ```bash
   aws logs tail /aws/lambda/vehicle-log-producer --follow
   aws logs tail /aws/lambda/vehicle-log-consumer --follow
   ```

3. **Review Terraform state**:
   ```bash
   terraform show
   terraform output
   ```

4. **AWS Console debugging**:
   - OpenSearch: Collections → error-logs-mock → Monitoring
   - EKS: Clusters → trainium-inferentia → Workloads
   - Lambda: Functions → Monitoring
   - CloudWatch: Logs Insights

### Common Questions

**Q: How do I know if data is being indexed?**
```bash
# Check document count (should increase ~100/minute)
awscurl --service aoss --region us-west-2 \
  -X GET "https://$(terraform output -raw opensearch_collection_endpoint)/error-logs-mock/_count"

# Check Lambda consumer logs
aws logs tail /aws/lambda/vehicle-log-consumer --filter-pattern "Completed" --follow
```

**Q: How do I test temporal queries?**
```bash
# Use Gradio UI with queries like:
# - "errors in the last 1 hour"
# - "battery issues in the last 2 days"
# - "engine failures in the last week"

# Check logs for confirmation
kubectl logs -l app=eks-rag | grep "Detected temporal filter"
# Output: Detected temporal filter: {'gte': 'now-1h'}
```

**Q: Can I use a different LLM?**
Yes, modify `vector_search_service.py`:
```python
# Change vLLM endpoint or use Bedrock runtime
# For Bedrock Claude:
response = bedrock_runtime.invoke_model(
    modelId="anthropic.claude-3-sonnet-20240229-v1:0",
    body=json.dumps({"messages": [...], "max_tokens": 1024})
)
```

**Q: How do I increase indexing throughput?**
```bash
# Increase Kinesis shard count
aws kinesis update-shard-count \
  --stream-name error-logs-stream \
  --target-shard-count 2 \
  --scaling-type UNIFORM_SCALING

# Increase Lambda concurrency
aws lambda put-function-concurrency \
  --function-name vehicle-log-consumer \
  --reserved-concurrent-executions 10
```

---

## License

This Terraform configuration is part of the Advanced RAG on EKS project.

---

## Changelog

### v2.0 - January 2025
- ✅ Added temporal query filtering ("last N hours/days/weeks/months")
- ✅ Added current datetime context to LLM system prompt
- ✅ Added timestamp field to vector search results
- ✅ Fixed OpenSearch index creation (awscurl implementation)
- ✅ Added proper dependency tracking via data_access_policy_id
- ✅ Enhanced README with comprehensive architecture diagrams
- ✅ Added detailed troubleshooting guide
- ✅ Added usage examples with temporal queries

### v1.0 - December 2024
- Initial release with RAG pipeline
- Lambda producer/consumer implementation
- OpenSearch Serverless integration
- Gradio UI deployment
- IRSA security configuration
