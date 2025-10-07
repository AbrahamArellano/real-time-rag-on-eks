# Complete Terraform Deployment Guide

## 📋 Overview

This guide provides step-by-step instructions for deploying the Advanced RAG on EKS application using Terraform automation.

**Deployment Time**: 15-25 minutes
**Estimated Cost**: ~$130-230/month

---

## 🎯 What Gets Deployed

### AWS Resources
- ✅ IAM Role with Bedrock + OpenSearch policies
- ✅ OpenSearch Serverless collection (VECTORSEARCH)
- ✅ ECR Repository with lifecycle policy
- ✅ Docker image (built and pushed)

### Kubernetes Resources
- ✅ ServiceAccount (with IAM role annotation)
- ✅ Deployment (2 replicas)
- ✅ LoadBalancer Service
- ✅ NetworkPolicy (vLLM + AWS egress)

### Data
- ✅ ~1000 sample logs (7 days of vehicle telemetry)
- ✅ Vector embeddings (via Bedrock Cohere)
- ✅ OpenSearch index with KNN search

---

## 🔧 Prerequisites

### Required Tools
| Tool | Version | Check Command |
|------|---------|---------------|
| Terraform | >= 1.5.0 | `terraform version` |
| AWS CLI | >= 2.0 | `aws --version` |
| kubectl | >= 1.28 | `kubectl version --client` |
| Docker | >= 20.0 | `docker version` |
| Python | >= 3.9 | `python3 --version` |

### Required AWS Resources
- EKS Cluster: `trainium-inferentia` (or configured name)
- vLLM Service: `vllm-llama3-inf2-serve-svc` in `vllm` namespace
- AWS Credentials: Configured with appropriate permissions

### Automated Prerequisite Check

Run the pre-flight check script:

```bash
cd eks-rag/terraform
./scripts/preflight-check.sh
```

This will validate all prerequisites and provide a ✓/✗ report.

---

## 🚀 Quick Start (Automated)

For rapid deployment without customization:

```bash
# 1. Navigate to terraform directory
cd eks-rag/terraform

# 2. Run preflight check
./scripts/preflight-check.sh

# 3. One-command deployment
terraform init && terraform apply -auto-approve
```

⏳ **Wait 15-25 minutes** for complete deployment.

---

## 📝 Standard Deployment (Step-by-Step)

### Step 1: Prepare Configuration

```bash
# Navigate to terraform directory
cd eks-rag/terraform

# Copy example configuration (optional - defaults work)
cp terraform.tfvars.example terraform.tfvars

# Edit if needed
vim terraform.tfvars
```

**Key variables to review:**
- `cluster_name`: Your EKS cluster name (default: trainium-inferentia)
- `aws_region`: AWS region (default: us-west-2)
- `replicas`: Number of pods (default: 2)

### Step 2: Initialize Terraform

```bash
terraform init
```

**Expected output:**
```
Initializing modules...
Initializing the backend...
Initializing provider plugins...
- Finding hashicorp/aws versions matching "~> 5.0"...
- Finding hashicorp/kubernetes versions matching "~> 2.23"...

Terraform has been successfully initialized!
```

### Step 3: Review Deployment Plan

```bash
terraform plan
```

**Review the plan:**
- Resources to be created: ~20-25 resources
- No resources should be destroyed (first run)
- Check resource names match expectations

**Expected resource count:**
- IAM: 4 resources (2 policies, 1 role, 2 attachments)
- OpenSearch: 4 resources (collection, 3 policies)
- ECR: 2 resources (repository, lifecycle policy)
- Kubernetes: 4 resources (SA, deployment, service, network policy)
- Data: 3 null_resources (dependencies, generate, index)
- Docker: 1 null_resource (build/push)

### Step 4: Apply Configuration

```bash
terraform apply
```

Type `yes` when prompted.

**Deployment phases:**

```
Phase 1: ECR Repository Creation (1-2 min)
└─ Creating repository: advanced-rag-mloeks/eks-rag

Phase 2: Docker Build & Push (3-5 min)
├─ Authenticating with ECR
├─ Building Docker image
└─ Pushing to ECR

Phase 3: IAM Resources (1-2 min)
├─ Creating Bedrock policy
├─ Creating OpenSearch policy
└─ Creating IRSA role

Phase 4: OpenSearch Collection (5-10 min) ⏳ LONGEST
├─ Creating encryption policy
├─ Creating network policy
├─ Creating collection (wait for ACTIVE)
└─ Creating data access policy

Phase 5: Kubernetes Deployment (2-3 min)
├─ Creating ServiceAccount
├─ Creating Deployment
├─ Creating Service (LoadBalancer)
└─ Creating NetworkPolicy

Phase 6: Data Indexing (3-5 min)
├─ Installing Python dependencies
├─ Generating sample logs
├─ Creating OpenSearch index
└─ Indexing with embeddings
```

**Total: 15-25 minutes**

### Step 5: Verify Deployment

```bash
# View all outputs
terraform output

# Check specific outputs
terraform output service_account_role_arn
terraform output opensearch_collection_endpoint
terraform output rag_service_endpoint
```

**Verify AWS resources:**

```bash
# IAM Role
aws iam get-role --role-name eks-rag-sa-role-trainium-inferentia

# OpenSearch Collection
aws opensearchserverless list-collections --region us-west-2 | grep error-logs-mock

# ECR Repository
aws ecr describe-repositories --repository-names advanced-rag-mloeks/eks-rag --region us-west-2
```

**Verify Kubernetes resources:**

```bash
# Service Account
kubectl get sa eks-rag-sa -o yaml

# Deployment
kubectl get deployment eks-rag
kubectl get pods -l app=eks-rag

# Service
kubectl get svc eks-rag-service

# Network Policy
kubectl get networkpolicy allow-vllm-access
```

**Check pod logs:**

```bash
# View recent logs
kubectl logs -l app=eks-rag --tail=50

# Follow logs
kubectl logs -l app=eks-rag -f

# Check pod status
kubectl describe pod -l app=eks-rag
```

---

## 🧪 Testing the Deployment

### Wait for LoadBalancer

```bash
# Get service endpoint
export SERVICE_IP=$(terraform output -raw rag_service_endpoint)

# If showing "pending", wait for LoadBalancer
while [ "$SERVICE_IP" = "pending" ]; do
  echo "Waiting for LoadBalancer provisioning..."
  sleep 10
  export SERVICE_IP=$(kubectl get svc eks-rag-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
done

echo "Service ready at: $SERVICE_IP"
```

### Test Health Endpoint

```bash
curl http://$SERVICE_IP/health

# Expected output:
# {"status":"healthy"}
```

### Test RAG Query

```bash
# Query 1: Engine temperature alerts
curl -X POST http://$SERVICE_IP/submit_query \
  -H "Content-Type: application/json" \
  -d '{"query": "Show critical engine temperature alerts"}' | jq .

# Query 2: Battery voltage issues
curl -X POST http://$SERVICE_IP/submit_query \
  -H "Content-Type: application/json" \
  -d '{"query": "Are there any vehicles with battery voltage below 11.5V?"}' | jq .

# Query 3: GPS issues
curl -X POST http://$SERVICE_IP/submit_query \
  -H "Content-Type: application/json" \
  -d '{"query": "Show vehicles with GPS signal loss"}' | jq .
```

**Expected response structure:**

```json
{
  "query": "...",
  "llm_response": "Based on the logs...",
  "similar_documents": [
    {
      "score": 0.89,
      "message": "Engine temperature sensor reading critical...",
      "service": "vehicle-telemetry",
      "error_code": "SENSOR_001",
      "vehicle_id": "VIN-1234",
      "sensor_readings": {...}
    }
  ],
  "processing_time": 2.34
}
```

---

## 🔄 Making Updates

### Update Application Code

If you modify the Python code:

```bash
# Terraform will detect changes and rebuild
terraform apply
```

### Update Configuration

```bash
# Edit configuration
vim terraform.tfvars

# Apply changes
terraform apply
```

### Force Docker Rebuild

```bash
# Taint the Docker build resource
terraform taint null_resource.docker_build_push

# Apply to rebuild and redeploy
terraform apply
```

### Re-index Data

```bash
# Taint the indexing resource
terraform taint module.data_indexing.null_resource.index_logs

# Apply to re-index
terraform apply
```

### Scale Deployment

```bash
# Edit terraform.tfvars
replicas = 3

# Apply changes
terraform apply
```

---

## 🛠️ Troubleshooting

### Issue: OpenSearch Collection Timeout

**Symptom**: Collection creation takes >15 minutes

**Solution**:
```bash
# Check collection status
aws opensearchserverless list-collections --region us-west-2

# Wait and retry if needed
terraform apply
```

### Issue: Docker Build Fails

**Symptom**: `Error: Docker build failed`

**Solutions**:
```bash
# 1. Check Docker is running
docker ps

# 2. Test ECR authentication
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin \
  $(aws sts get-caller-identity --query Account --output text).dkr.ecr.us-west-2.amazonaws.com

# 3. Manual build test
cd ../
docker build -t test .
```

### Issue: Data Indexing Fails

**Symptom**: `Error: Failed to index logs`

**Solutions**:
```bash
# 1. Check Python dependencies
pip3 list | grep -E "boto3|opensearch-py|requests-aws4auth"

# 2. Install missing dependencies
pip3 install boto3 opensearch-py requests-aws4auth

# 3. Run indexing manually
cd ../../opensearch-setup
python3 generate_logs.py
python3 index_logs.py
```

### Issue: Pods CrashLoopBackOff

**Symptom**: Pods continuously restarting

**Solutions**:
```bash
# Check pod logs
kubectl logs -l app=eks-rag --tail=100

# Common causes:
# 1. IAM permissions - Check service account annotation
# 2. OpenSearch access - Check collection is ACTIVE
# 3. vLLM connectivity - Check network policy

# Verify IAM role annotation
kubectl get sa eks-rag-sa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Test OpenSearch access from pod
kubectl exec -it $(kubectl get pod -l app=eks-rag -o jsonpath='{.items[0].metadata.name}') -- \
  curl -v https://$(terraform output -raw opensearch_collection_endpoint)

# Check vLLM service
kubectl get svc -n vllm vllm-llama3-inf2-serve-svc
```

### Issue: LoadBalancer Pending

**Symptom**: Service endpoint shows "pending"

**Solutions**:
```bash
# 1. Check AWS Load Balancer Controller
kubectl get deployment -n kube-system aws-load-balancer-controller

# 2. Check service events
kubectl describe svc eks-rag-service

# 3. Wait (can take 2-3 minutes)
kubectl get svc eks-rag-service -w
```

### Issue: IAM Role Not Assumed

**Symptom**: Pods can't access AWS services

**Solutions**:
```bash
# 1. Verify OIDC provider exists
aws eks describe-cluster --name trainium-inferentia --region us-west-2 \
  --query 'cluster.identity.oidc.issuer' --output text

# 2. Verify role trust policy
aws iam get-role --role-name eks-rag-sa-role-trainium-inferentia \
  --query 'Role.AssumeRolePolicyDocument'

# 3. Check service account annotation
kubectl get sa eks-rag-sa -o yaml
```

---

## 🧹 Cleanup

### Complete Removal

```bash
# Destroy all resources
terraform destroy

# Type 'yes' when prompted
```

**Resources deleted:**
- All Kubernetes resources
- OpenSearch collection
- IAM role and policies
- ECR repository and images

**Cleanup time**: 5-10 minutes

### Partial Cleanup

```bash
# Remove only Kubernetes resources
terraform destroy -target=module.kubernetes

# Remove only data indexing
terraform destroy -target=module.data_indexing

# Remove only OpenSearch
terraform destroy -target=module.opensearch
```

---

## 📊 Monitoring & Logs

### View Pod Logs

```bash
# All pods
kubectl logs -l app=eks-rag --tail=100

# Specific pod
kubectl logs <pod-name>

# Follow logs
kubectl logs -l app=eks-rag -f

# Previous container logs (if crashed)
kubectl logs <pod-name> --previous
```

### Check Resource Usage

```bash
# Pod metrics
kubectl top pod -l app=eks-rag

# Node metrics
kubectl top nodes
```

### CloudWatch Logs (Optional)

If CloudWatch logging is enabled:

```bash
# View log groups
aws logs describe-log-groups --region us-west-2

# Tail logs
aws logs tail /aws/eks/trainium-inferentia/cluster --follow
```

---

## 📈 Performance & Scaling

### Horizontal Scaling

```bash
# Edit terraform.tfvars
replicas = 5

# Apply
terraform apply

# Or use kubectl directly
kubectl scale deployment eks-rag --replicas=5
```

### Vertical Scaling

Edit `modules/kubernetes/main.tf`:

```hcl
resources {
  requests = {
    cpu    = "500m"
    memory = "512Mi"
  }
  limits = {
    cpu    = "1000m"
    memory = "1Gi"
  }
}
```

Then apply:

```bash
terraform apply
```

---

## 🔐 Security Best Practices

### For Production

1. **Private OpenSearch**:
   ```hcl
   # In terraform.tfvars
   allow_public_opensearch = false
   ```

2. **VPC Endpoints**: Configure for ECR, OpenSearch, Bedrock

3. **Network Policies**: Restrict egress to specific CIDRs

4. **Image Tags**: Use immutable tags instead of `:latest`

5. **Secrets**: Use AWS Secrets Manager for sensitive data

6. **Monitoring**: Enable CloudWatch logs and X-Ray tracing

7. **State Backend**: Use S3 with DynamoDB locking

---

## 📚 Additional Resources

- **Full Documentation**: See [README.md](README.md)
- **Quick Reference**: See [QUICKSTART.md](QUICKSTART.md)
- **Implementation Details**: See [IMPLEMENTATION_SUMMARY.md](IMPLEMENTATION_SUMMARY.md)
- **Main Project**: See [../../README.md](../../README.md)

---

## ✅ Success Criteria

Your deployment is successful when:

1. ✅ `terraform apply` completes without errors
2. ✅ All outputs are displayed (no "pending" values after 5 min)
3. ✅ Pods are Running and Ready (2/2)
4. ✅ Health endpoint returns 200 OK
5. ✅ Test query returns LLM response with similar documents
6. ✅ No errors in pod logs

---

## 💰 Cost Management

### Monthly Cost Breakdown

| Service | Cost | Optimization |
|---------|------|--------------|
| OpenSearch Serverless | $100-200 | Use reserved capacity |
| Network Load Balancer | $18-20 | Share across services |
| ECR Storage | $1-5 | Lifecycle policies (automated) |
| Bedrock API | $1-10 | Cache embeddings |
| Data Transfer | $5-10 | Use VPC endpoints |
| **Total** | **$125-245** | |

### Cost Optimization Tips

1. **Stop when not in use**: `terraform destroy` when testing
2. **Use Spot instances**: For non-critical workloads
3. **Share Load Balancer**: Use Ingress for multiple services
4. **Cache embeddings**: Reduce Bedrock API calls
5. **Monitor usage**: Set up billing alerts

---

## 🆘 Getting Help

1. **Run preflight check**: `./scripts/preflight-check.sh`
2. **Check pod logs**: `kubectl logs -l app=eks-rag`
3. **Review Terraform output**: `terraform output`
4. **Check AWS CloudTrail**: For API errors
5. **Verify prerequisites**: All tools installed and configured

**Common Issues**: See Troubleshooting section above

---

## 🎉 Congratulations!

If you've reached this point, you have successfully deployed a production-ready RAG application on EKS using Terraform!

**Next Steps**:
- Deploy the optional UI
- Set up monitoring and alerting
- Configure auto-scaling
- Implement CI/CD pipeline
- Review security hardening

Happy deploying! 🚀
