Bootstrap for remote state backend resources.

Usage:

```bash
cd infra/eks-terraform/backend-bootstrap
terraform init
terraform apply -var="aws_region=us-east-1"

# After apply note outputs `bucket` and `dynamodb_table`.
```

Use the printed `bucket` and `dynamodb_table` values when initializing the main EKS terraform backend (see main README).
