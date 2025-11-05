# dev2 Environment Decommissioning Guide

## Overview
Complete checklist for removing the dev2 environment from all Aloware infrastructure.

---

## ✅ Completed Steps

### 1. Jenkins Pipeline Configuration
- [x] Removed dev2 from `helm-deploy/Jenkinsfile` ENV choices
- [x] Removed 3 dev2 case statements from `helm-deploy/Jenkinsfile`
- [x] Removed `values/dev2.yaml` reference
- [x] Updated `ansible-rollback/Jenkinsfile` description
- [x] PR created: #18

---

## 🔄 Remaining Steps

### 2. AWS Systems Manager (Parameter Store) Cleanup

**Account:** `333629833033` (Dev Account - us-west-2)

#### Check what parameters exist:
```bash
# List all dev2 parameters
aws ssm get-parameters-by-path \
  --path "/dev2/api-core/app/" \
  --recursive \
  --profile dev \
  --query "Parameters[].Name" \
  --output table

# Count them
aws ssm get-parameters-by-path \
  --path "/dev2/api-core/app/" \
  --recursive \
  --profile dev \
  --query "Parameters[].Name" \
  --output text | wc -w
```

#### Known parameters to delete:
- `/dev2/api-core/app/GOOGLE_SHEETS_API_CLIENT_X509_CERT_URL`
- Likely 50+ more parameters (same as dev1)

#### Delete all dev2 parameters:

**⚠️ CAUTION:** This is irreversible. Backup first!

```bash
# Step 1: Backup all dev2 parameters (IMPORTANT!)
aws ssm get-parameters-by-path \
  --path "/dev2/api-core/app/" \
  --recursive \
  --with-decryption \
  --profile dev \
  --output json > ~/backup-dev2-parameters-$(date +%Y%m%d).json

echo "✅ Backup saved to ~/backup-dev2-parameters-$(date +%Y%m%d).json"

# Step 2: Get list of all parameter names
DEV2_PARAMS=$(aws ssm get-parameters-by-path \
  --path "/dev2/api-core/app/" \
  --recursive \
  --profile dev \
  --query "Parameters[].Name" \
  --output text)

# Step 3: Count them
PARAM_COUNT=$(echo "$DEV2_PARAMS" | wc -w)
echo "Found $PARAM_COUNT parameters to delete"

# Step 4: Delete them one by one (AWS doesn't support bulk delete for paths)
for param in $DEV2_PARAMS; do
  echo "Deleting $param..."
  aws ssm delete-parameter --name "$param" --profile dev
  sleep 0.5  # Rate limit protection
done

echo "✅ All dev2 parameters deleted"

# Step 5: Verify deletion
REMAINING=$(aws ssm get-parameters-by-path \
  --path "/dev2/api-core/app/" \
  --recursive \
  --profile dev \
  --query "Parameters[].Name" \
  --output text | wc -w)

if [ "$REMAINING" -eq "0" ]; then
  echo "✅ Verification passed: No dev2 parameters remain"
else
  echo "❌ Warning: $REMAINING parameters still exist"
fi
```

**Alternative: Delete via AWS Console:**
1. Go to: https://us-west-2.console.aws.amazon.com/systems-manager/parameters
2. Filter by path: `/dev2/api-core/app/`
3. Select all
4. Actions → Delete parameters

---

### 3. Kubernetes Resources Cleanup

**Cluster:** `aloware-dev-uswest2-eks-cluster-cr-01`  
**Namespace:** `app2` (this is dev2's namespace)

#### Check if namespace exists and what's in it:
```bash
# Configure kubectl for dev cluster
aws eks update-kubeconfig \
  --name aloware-dev-uswest2-eks-cluster-cr-01 \
  --region us-west-2 \
  --profile dev

# Check if app2 namespace exists
kubectl get namespace app2

# If it exists, see what's running
kubectl get all -n app2

# Check for persistent volumes
kubectl get pvc -n app2

# Check for secrets
kubectl get secrets -n app2

# Check for configmaps
kubectl get configmaps -n app2
```

#### Delete the namespace (if it exists):

**⚠️ CAUTION:** This deletes all resources in the namespace!

```bash
# Backup resources first (optional)
kubectl get all -n app2 -o yaml > ~/backup-app2-namespace-$(date +%Y%m%d).yaml

# Delete the namespace
kubectl delete namespace app2

# Verify deletion
kubectl get namespace app2
# Should return: Error from server (NotFound): namespaces "app2" not found
```

---

### 4. Helm Values File (if exists in separate repo)

**Repository:** `aloware/helm-api-core`

Check if `values/dev2.yaml` exists in the Helm chart repository:

```bash
# Clone the Helm repo
git clone https://github.com/aloware/helm-api-core.git
cd helm-api-core

# Check if dev2 values file exists
ls -la values/dev2.yaml

# If it exists, remove it
git rm values/dev2.yaml
git commit -m "Remove dev2 values file - environment decommissioned"
git push origin main
```

---

### 5. AWS ECR Images (Optional Cleanup)

**Registry:** `333629833033.dkr.ecr.us-west-2.amazonaws.com`  
**Repository:** `api-core`

dev2 deployments may have created ECR images with dev2-specific tags.

#### Check for dev2-tagged images:
```bash
# List images with dev2 in tag
aws ecr list-images \
  --repository-name api-core \
  --profile dev \
  --region us-west-2 \
  --query "imageIds[?contains(imageTag, 'dev2')]" \
  --output table

# Optional: Delete dev2-tagged images
# Only if you're sure they're not being used elsewhere
# (Usually safe to skip this step)
```

---

### 6. Infrastructure as Code Updates

If you have Terraform/CloudFormation/etc. for dev2 infrastructure:

#### Terraform:
```bash
cd infrastructure/terraform/dev2

# Remove the dev2 environment
terraform destroy

# Delete the directory
cd ..
rm -rf dev2

# Commit the changes
git rm -r dev2
git commit -m "Remove dev2 environment infrastructure"
git push
```

#### Ansible Inventories:
Check if `inventories/non-production/dev2` exists in `aloware-ansible-templates`:

```bash
git clone https://github.com/aloware/aloware-ansible-templates.git
cd aloware-ansible-templates

# Check for dev2 inventory
ls -la inventories/non-production/dev2

# If exists, remove it
git rm -r inventories/non-production/dev2
git commit -m "Remove dev2 inventory - environment decommissioned"
git push
```

---

### 7. DNS/Load Balancer (if applicable)

If dev2 had its own domain/load balancer:

#### Check Route53:
```bash
# List hosted zones
aws route53 list-hosted-zones --profile dev

# Check for dev2 DNS records
aws route53 list-resource-record-sets \
  --hosted-zone-id <ZONE_ID> \
  --profile dev \
  --query "ResourceRecordSets[?contains(Name, 'dev2')]"
```

#### Check Load Balancers:
```bash
# List ALBs
aws elbv2 describe-load-balancers \
  --profile dev \
  --region us-west-2 \
  --query "LoadBalancers[?contains(LoadBalancerName, 'dev2')]"

# If found, delete it
aws elbv2 delete-load-balancer \
  --load-balancer-arn <ARN> \
  --profile dev \
  --region us-west-2
```

---

### 8. Monitoring/Alerting Cleanup

#### CloudWatch Dashboards:
```bash
# List dashboards
aws cloudwatch list-dashboards --profile dev --region us-west-2

# If dev2 dashboard exists
aws cloudwatch delete-dashboards \
  --dashboard-names "dev2-api-core" \
  --profile dev \
  --region us-west-2
```

#### CloudWatch Alarms:
```bash
# List alarms for dev2
aws cloudwatch describe-alarms \
  --alarm-name-prefix "dev2" \
  --profile dev \
  --region us-west-2

# Delete specific alarms
aws cloudwatch delete-alarms \
  --alarm-names "dev2-high-cpu" "dev2-high-memory" \
  --profile dev \
  --region us-west-2
```

---

### 9. Database Cleanup (if dev2 had dedicated DB)

#### Check RDS:
```bash
# List RDS instances
aws rds describe-db-instances \
  --profile dev \
  --region us-west-2 \
  --query "DBInstances[?contains(DBInstanceIdentifier, 'dev2')]"

# If found and you want to delete (CAUTION!)
# Take a final snapshot first
aws rds create-db-snapshot \
  --db-instance-identifier <dev2-db-id> \
  --db-snapshot-identifier dev2-final-snapshot-$(date +%Y%m%d) \
  --profile dev \
  --region us-west-2

# Then delete
aws rds delete-db-instance \
  --db-instance-identifier <dev2-db-id> \
  --skip-final-snapshot \
  --profile dev \
  --region us-west-2
```

---

### 10. Documentation Updates

Update any documentation that references dev2:

- [ ] Wiki/Confluence pages
- [ ] README files
- [ ] Onboarding docs
- [ ] Architecture diagrams
- [ ] Runbooks
- [ ] Incident response procedures

---

## 🔍 Verification Checklist

After cleanup, verify everything is gone:

```bash
# 1. Check AWS SSM
aws ssm get-parameters-by-path --path "/dev2/" --recursive --profile dev
# Should return: empty list

# 2. Check Kubernetes
kubectl get namespace app2
# Should return: NotFound

# 3. Check Jenkins
# Verify dev2 is not in any dropdown or description

# 4. Check ECR
aws ecr describe-images --repository-name api-core --profile dev --query "imageIds[?contains(imageTag, 'dev2')]"
# Should return: empty list

# 5. Check load balancers
aws elbv2 describe-load-balancers --profile dev --query "LoadBalancers[?contains(LoadBalancerName, 'dev2')]"
# Should return: empty list
```

---

## 📊 Cost Savings Estimate

After full dev2 decommissioning:
- **Kubernetes nodes:** ~$100-200/month (if dedicated)
- **RDS instance:** ~$50-150/month (if dedicated)
- **Load balancer:** ~$20/month
- **EBS volumes:** ~$10/month
- **CloudWatch logs:** ~$5/month
- **Parameter Store:** Free
- **ECR storage:** ~$1/month

**Total estimated savings:** $186-386/month ($2,232-4,632/year)

---

## 🚨 Rollback Plan

If you need to restore dev2:

### 1. Restore AWS Parameters:
```bash
# Use the backup created earlier
BACKUP_FILE=~/backup-dev2-parameters-YYYYMMDD.json

# Parse and restore each parameter
cat $BACKUP_FILE | jq -r '.Parameters[] | 
  "aws ssm put-parameter --name \(.Name) --value '\''\(.Value)'\'' --type \(.Type) --profile dev"' | 
  bash
```

### 2. Recreate Kubernetes namespace:
```bash
kubectl create namespace app2
kubectl apply -f ~/backup-app2-namespace-YYYYMMDD.yaml
```

### 3. Revert Jenkins changes:
```bash
git revert <commit-hash>
```

---

## 📅 Recommended Timeline

**Week 1:** 
- ✅ Jenkins pipeline changes (completed)
- ✅ Code reviews and testing

**Week 2:**
- [ ] Notify all dev2 users
- [ ] Provide migration path to dev1 or new MDE
- [ ] Freeze new deployments to dev2

**Week 3:**
- [ ] Backup all dev2 data
- [ ] Delete AWS SSM parameters
- [ ] Delete Kubernetes namespace
- [ ] Delete Helm values

**Week 4:**
- [ ] Cleanup remaining resources (ECR, monitoring, etc.)
- [ ] Verify all resources deleted
- [ ] Update documentation

---

## 👥 Stakeholders to Notify

Before starting cleanup:
- [ ] Development team
- [ ] QA team
- [ ] DevOps team
- [ ] Product managers
- [ ] Anyone with access to Jenkins dev2 deployments

---

## 📞 Support

If issues arise during cleanup:
- DevOps team: #dev-ops Slack channel
- AWS console: https://console.aws.amazon.com
- Kubernetes dashboard: (if available)

---

**Created:** November 3, 2025  
**Last Updated:** November 3, 2025  
**Status:** In Progress  
**Owner:** DevOps Team
