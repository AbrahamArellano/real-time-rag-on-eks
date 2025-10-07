# Quick Start Guide - Terraform Deployment

## Prerequisites Check

```bash
# 1. Verify you're in the right directory
cd eks-rag/terraform

# 2. Check EKS access
kubectl get nodes
# Expected: List of nodes in trainium-inferentia cluster

# 3. Check vLLM service
kubectl get svc -n vllm vllm-llama3-inf2-serve-svc
# Expected: Service with ClusterIP on port 8000

# 4. Check AWS credentials
aws sts get-caller-identity
# Expected: Your AWS account details

# 5. Check Docker
docker ps
# Expected: Docker daemon running
```

## One-Command Deployment

```bash
# Initialize and apply in one go
terraform init && terraform apply -auto-approve
```

This will take **15-25 minutes** to complete.

## What Gets Created

1. **IAM Role**: `eks-rag-sa-role-trainium-inferentia` with Bedrock + OpenSearch policies
2. **OpenSearch Collection**: `error-logs-mock` (VECTORSEARCH type)
3. **ECR Repository**: `advanced-rag-mloeks/eks-rag` with lifecycle policy
4. **Docker Image**: Built from `eks-rag/` and pushed to ECR
5. **Kubernetes Resources**:
   - ServiceAccount: `eks-rag-sa` (with IAM role annotation)
   - Deployment: `eks-rag` (2 replicas)
   - Service: `eks-rag-service` (LoadBalancer type)
   - NetworkPolicy: `allow-vllm-access`
6. **Sample Data**: ~1000 logs indexed with vector embeddings

## Deployment Progress

You'll see these phases:

```
Phase 1: Creating ECR repository... (1-2 min)
Phase 2: Building and pushing Docker image... (3-5 min)
Phase 3: Creating IAM resources... (1-2 min)
Phase 4: Creating OpenSearch collection... (5-10 min) ⏳ LONGEST STEP
Phase 5: Deploying Kubernetes resources... (2-3 min)
Phase 6: Indexing sample data... (3-5 min)
```

## Testing

```bash
# 1. Get the service endpoint
export SERVICE_IP=$(terraform output -raw rag_service_endpoint)

# 2. Wait for LoadBalancer (if needed)
while [ "$SERVICE_IP" = "pending" ]; do
  echo "Waiting for LoadBalancer..."
  sleep 10
  export SERVICE_IP=$(terraform output -raw rag_service_endpoint)
done

# 3. Test health endpoint
curl http://$SERVICE_IP/health

# 4. Test with a query
curl -X POST http://$SERVICE_IP/submit_query \
  -H "Content-Type: application/json" \
  -d '{"query": "Show critical engine temperature alerts"}' | jq .
```

## Troubleshooting

### If deployment fails:

```bash
# Check what was created
terraform show

# Check specific module
terraform state list | grep module.opensearch

# Retry specific module
terraform apply -target=module.opensearch
```

### If pods are crashing:

```bash
# Check pod status
kubectl get pods -l app=eks-rag

# View logs
kubectl logs -l app=eks-rag --tail=100

# Common issues:
# - IAM permissions: Check service account annotation
# - OpenSearch access: Check collection is ACTIVE
# - vLLM connectivity: Check network policy
```

### If data indexing fails:

```bash
# Check Python dependencies
pip3 list | grep -E "boto3|opensearch-py"

# Run manually
cd ../../opensearch-setup
python3 generate_logs.py
python3 index_logs.py
```

## Cleanup

```bash
# Destroy everything
terraform destroy -auto-approve
```

This will delete all resources created by Terraform. Takes ~5-10 minutes.

## Next Steps

After successful deployment:

1. **Deploy UI** (optional):
   ```bash
   cd ../../ui
   # Update deployment.yaml with your account ID
   # Build and push UI image
   # Deploy UI
   ```

2. **Monitor**: Check CloudWatch logs for the pods

3. **Scale**: Adjust `replicas` in `terraform.tfvars` and re-apply

4. **Production**: Review security settings in README.md

## Key Outputs

```bash
# View all outputs
terraform output

# Individual outputs
terraform output service_account_role_arn
terraform output opensearch_collection_endpoint
terraform output rag_service_endpoint
```

## Cost

Approximate costs:
- OpenSearch Serverless: ~$100-200/month
- LoadBalancer: ~$20/month
- Other services: ~$10/month
- **Total: ~$130-230/month**

## Support

- Full documentation: See `README.md`
- Main project: See `../../README.md`
- Issues: Check pod logs and Terraform output
