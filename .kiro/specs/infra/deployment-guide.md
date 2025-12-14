# Java-on-AWS Deployment Guide

## Generate Templates
```bash
cd infra
TEMPLATE_TYPE=java-on-aws npm run generate
```

## Deploy Stack
```bash
# Deploy stack (uses existing S3 bucket for large templates)
aws cloudformation deploy \
  --template-file cfn/java-on-aws-stack.yaml \
  --stack-name workshop-stack \
  --capabilities CAPABILITY_IAM CAPABILITY_NAMED_IAM \
  --s3-bucket workshop-cfn-templates-973079160866
```

## Architecture Fixes Applied
1. **Fixed bootstrap failure rollback issue**: Removed WaitCondition dependencies from critical outputs to match original working architecture. Stack will still fail if bootstrap fails, but will rollback cleanly without orphaned resources.
2. **Fixed EKS startup delay**: Refactored role creation to match original architecture - role is created in props and shared between IDE and EKS, eliminating CloudFormation dependency that delayed EKS cluster creation.

## Test & Debug

### Get Stack Outputs
```bash
source .env
aws cloudformation describe-stacks --stack-name workshop-stack --query 'Stacks[0].Outputs'
```

### Check Bootstrap Logs
```bash
source .env
# Find log group (format: ide-bootstrap-YYYYMMDD-HHMMSS)
aws logs describe-log-groups --log-group-name-prefix "ide-bootstrap"

# Get logs
aws logs get-log-events \
  --log-group-name "ide-bootstrap-YYYYMMDD-HHMMSS" \
  --log-stream-name "i-instanceid" \
  --start-from-head --output text
```

### Check EKS Cluster
```bash
source .env
aws eks describe-cluster --name workshop-eks
kubectl get nodes
kubectl get pods -A
```

### Verify Database
```bash
source .env
aws rds describe-db-clusters --db-cluster-identifier workshop-db-cluster
aws secretsmanager get-secret-value --secret-id workshop-db-secret
```

## Git Workflow
```bash
git add .
git commit -m "Update infrastructure"
git push origin new-ws-infra
```

**Note**: Always `source .env` first for AWS CLI access with proper credentials.