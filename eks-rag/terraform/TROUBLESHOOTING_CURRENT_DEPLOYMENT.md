# Current Deployment Troubleshooting Guide

**Status**: Deployment partially failed - needs investigation and remediation

---

## Current State Analysis

### ✅ Successfully Created Resources

Based on Terraform state, the following were created successfully:

1. **IAM Resources** ✅
   - Role: `eks-rag-sa-role-trainium-inferentia`
   - ARN: `arn:aws:iam::533267377863:role/eks-rag-sa-role-trainium-inferentia`
   - Bedrock policy attached
   - OpenSearch policy attached

2. **OpenSearch Serverless** ✅
   - Collection ID: `f9m70n04yrb5khswrg20`
   - Endpoint: `f9m70n04yrb5khswrg20.us-west-2.aoss.amazonaws.com`
   - ARN: `arn:aws:aoss:us-west-2:533267377863:collection/f9m70n04yrb5khswrg20`

3. **ECR Repository** ✅
   - Repository: `533267377863.dkr.ecr.us-west-2.amazonaws.com/advanced-rag-mloeks/eks-rag`
   - Image pushed: `latest` tag

4. **Kubernetes Resources** ⚠️ CREATED BUT FAILING
   - ServiceAccount: `eks-rag-sa` (created)
   - Deployment: `eks-rag` (created but TAINTED - rollout failed)
   - Service: Not visible in state (may not have been created)
   - NetworkPolicy: Not visible in state (may not have been created)

### ❌ Failed/Incomplete Resources

1. **Data Indexing** ❌
   - Error: Path resolution issue
   - `generate_logs.py` - FAILED (path not found)
   - `index_logs.py` - NOT RUN (depends on generate_logs)
   - **Issue**: `chdir modules/data-indexing/../../opensearch-setup: no such file or directory`

2. **Kubernetes Deployment** ❌
   - Status: TAINTED (rollout timeout after 10 minutes)
   - Pods: Not ready (0/2 replicas)
   - **Issue**: "Waiting for rollout to finish: 2 replicas wanted; 0 replicas Ready"

---

## Root Cause Analysis

### Issue 1: Path Resolution in Data Indexing Module
**Problem**: Used `path.module` which resolves incorrectly from nested modules
**Status**: ✅ FIXED in latest code (changed to `path.root`)
**Action Needed**: Re-apply Terraform to use fixed code

### Issue 2: Python Package Installation
**Problem**: macOS externally-managed Python environment
**Status**: ✅ FIXED in latest code (added `--user` and `--break-system-packages` flags)
**Action Needed**: Re-apply Terraform to use fixed code

### Issue 3: Pod Deployment Failure (ImagePullBackOff)
**Problem**: Pods not becoming ready - ImagePullBackOff error
**Root Cause**: Docker image platform mismatch
- Image was built on macOS ARM64 (Apple Silicon)
- EKS nodes are Linux AMD64
- Error: "no match for platform in manifest: not found"

**Status**: ✅ FIXED in latest code
**Fixes Applied**:
1. Added `--platform linux/amd64` flag to build-and-push.sh
2. Added platform trigger in main.tf to force rebuild
3. Created rebuild-fix-platform.sh automated fix script

**Action Needed**: Run `./scripts/rebuild-fix-platform.sh` to apply fixes

---

## Diagnostic Commands

### Run the Comprehensive Diagnostic Script

```bash
cd eks-rag/terraform
./scripts/diagnose-deployment.sh > deployment-diagnosis.log 2>&1
cat deployment-diagnosis.log
```

This will check:
1. Terraform outputs
2. Kubernetes resources (pods, deployments, services)
3. Pod status and events
4. Pod logs
5. IAM role configuration
6. OpenSearch collection status
7. ECR image details
8. vLLM service connectivity
9. Data indexing status
10. Network policies
11. Recommended actions

### Manual Checks

```bash
# 1. Check pod status
kubectl get pods -l app=eks-rag -o wide

# 2. Describe pods for events
kubectl describe pod -l app=eks-rag

# 3. Check pod logs
kubectl logs -l app=eks-rag --tail=100

# 4. Check deployment status
kubectl get deployment eks-rag -o yaml

# 5. Verify service account
kubectl get sa eks-rag-sa -o yaml

# 6. Check if service was created
kubectl get svc eks-rag-service

# 7. Check network policy
kubectl get networkpolicy allow-vllm-access
```

---

## Remediation Steps

### Recommended: Automated Fix Script

The fastest way to fix the platform issue is to use the automated script:

```bash
cd eks-rag/terraform
./scripts/rebuild-fix-platform.sh
```

This script will:
1. Taint the Docker build resource
2. Rebuild image with `--platform linux/amd64`
3. Push corrected image to ECR
4. Delete failed pods
5. Wait for new pods to become ready
6. Complete full Terraform deployment

### Alternative: Manual Fix

If you prefer manual steps:

#### Step 1: Verify Code Fixes

All fixes have been applied to the following files:
- ✅ `modules/data-indexing/main.tf` - Fixed path resolution and pip install
- ✅ `scripts/build-and-push.sh` - Added `--platform linux/amd64` flag
- ✅ `main.tf` - Added platform trigger to force rebuild

#### Step 2: Rebuild Docker Image

```bash
cd eks-rag/terraform

# Taint the Docker build to force rebuild
terraform taint null_resource.docker_build_push

# Rebuild with correct platform
terraform apply -target=null_resource.docker_build_push -auto-approve
```

#### Step 3: Delete Failed Pods

```bash
# Delete pods in ImagePullBackOff state
kubectl delete pods -l app=eks-rag

# Wait for new pods to be ready
kubectl wait --for=condition=ready pod -l app=eks-rag --timeout=300s
```

#### Step 4: Complete Deployment

```bash
# Apply full Terraform to create Service and NetworkPolicy
terraform apply -auto-approve

# Monitor deployment
kubectl get pods -l app=eks-rag -w
```

### Step 4: If Pods Still Fail - Deep Dive

If pods are still not starting, check specific issues:

#### A. Image Pull Issues
```bash
kubectl describe pod -l app=eks-rag | grep -A 5 "Image:"
kubectl describe pod -l app=eks-rag | grep -A 5 "Events:"
```

**Fix if needed**:
- Verify ECR image exists: `aws ecr describe-images --repository-name advanced-rag-mloeks/eks-rag --region us-west-2`
- Check image pull policy in deployment

#### B. Application Startup Failures
```bash
kubectl logs -l app=eks-rag --tail=100
```

**Common issues**:
- OpenSearch connection failures → Check collection endpoint and IAM permissions
- Bedrock API failures → Check IAM policy for InvokeModel
- vLLM unreachable → Check network policy and vLLM service

#### C. IAM Role Not Assumed
```bash
# Check service account annotation
kubectl get sa eks-rag-sa -o jsonpath='{.metadata.annotations.eks\.amazonaws\.com/role-arn}'

# Should output: arn:aws:iam::533267377863:role/eks-rag-sa-role-trainium-inferentia

# Test from pod
kubectl exec -it <pod-name> -- env | grep AWS
```

**Fix if needed**:
- Verify OIDC provider exists for cluster
- Verify trust policy on IAM role
- Verify role ARN matches annotation

#### D. OpenSearch Connectivity
```bash
# Test from pod
kubectl exec -it <pod-name> -- curl -v https://f9m70n04yrb5khswrg20.us-west-2.aoss.amazonaws.com
```

**Fix if needed**:
- Check OpenSearch access policy includes IAM role
- Verify network allows HTTPS to AWS services
- Check if collection is ACTIVE

---

## Expected Behavior After Remediation

### Successful Deployment Should Show:

```bash
# Pods running and ready
$ kubectl get pods -l app=eks-rag
NAME                       READY   STATUS    RESTARTS   AGE
eks-rag-xxxxxxxxxx-xxxxx   1/1     Running   0          2m
eks-rag-xxxxxxxxxx-xxxxx   1/1     Running   0          2m

# Service with external endpoint
$ kubectl get svc eks-rag-service
NAME              TYPE           CLUSTER-IP      EXTERNAL-IP                          PORT(S)        AGE
eks-rag-service   LoadBalancer   172.20.xx.xx    xxx.us-west-2.elb.amazonaws.com      80:xxxxx/TCP   5m

# Deployment ready
$ kubectl get deployment eks-rag
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
eks-rag   2/2     2            2           5m

# Data indexed
$ ls -lh ../../opensearch-setup/error_logs.json
-rw-r--r--  1 user  staff   XXX KB  <date>  error_logs.json
```

### Test the Service

```bash
# Get service endpoint
export SERVICE_IP=$(kubectl get svc eks-rag-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Wait for LoadBalancer
while [ -z "$SERVICE_IP" ]; do
  sleep 10
  export SERVICE_IP=$(kubectl get svc eks-rag-service -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
done

# Test health endpoint
curl http://$SERVICE_IP/health

# Test RAG query
curl -X POST http://$SERVICE_IP/submit_query \
  -H "Content-Type: application/json" \
  -d '{"query": "Show critical engine temperature alerts"}' | jq .
```

---

## Known Issues & Workarounds

### Issue: Deployment Timeout (10 minutes)
**Cause**: Kubernetes default `progress_deadline_seconds` is 600
**Workaround**: Increase timeout or fix underlying issue causing slow startup

### Issue: Python Package Installation on macOS
**Cause**: PEP 668 externally-managed environment
**Fix Applied**: Use `--user` or `--break-system-packages` flag

### Issue: Path Resolution in Modules
**Cause**: `path.module` vs `path.root` confusion
**Fix Applied**: Use `path.root` for accessing terraform root directory

---

## Emergency Rollback

If remediation fails and you need to start over:

```bash
# Complete teardown
cd eks-rag/terraform
terraform destroy

# Clean up any stuck resources
kubectl delete deployment eks-rag --force --grace-period=0
kubectl delete svc eks-rag-service --force --grace-period=0
kubectl delete sa eks-rag-sa

# Re-deploy from scratch
terraform init
terraform apply
```

---

## Next Steps

1. **Run diagnostics**: `./scripts/diagnose-deployment.sh`
2. **Review output**: Identify specific failure reason
3. **Apply remediation**: Follow steps above based on failure
4. **Test service**: Verify application works end-to-end
5. **Report findings**: Document what worked/what didn't

---

## Support Information

**Terraform State**: Visible via `terraform show`
**AWS Account**: 533267377863
**Region**: us-west-2
**Cluster**: trainium-inferentia
**Namespace**: default

**Key Resources**:
- IAM Role ARN: `arn:aws:iam::533267377863:role/eks-rag-sa-role-trainium-inferentia`
- OpenSearch Collection: `f9m70n04yrb5khswrg20`
- ECR Repository: `533267377863.dkr.ecr.us-west-2.amazonaws.com/advanced-rag-mloeks/eks-rag`
