# Java-on-AWS Deployment Guide

## Generate Templates
```bash
cd infra
TEMPLATE_TYPE=java-on-aws npm run generate
```

## Deploy Stack
```bash
aws cloudformation deploy \
  --template-file cfn/java-on-aws-stack.yaml \
  --stack-name workshop-stack \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    ParameterKey=ParameterName,ParameterValue=Value
```

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
aws eks describe-cluster --name workshop-cluster
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