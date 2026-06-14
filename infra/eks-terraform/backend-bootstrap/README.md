Bootstrap for remote state backend resources.

Usage:

```bash
cd infra/eks-terraform/backend-bootstrap
terraform init
terraform apply -var="aws_region=us-east-1"

# After apply note outputs `bucket` and `dynamodb_table`.
```

Use the printed `bucket` and optionally `dynamodb_table` values when initializing the main EKS terraform backend (see main README).

If you do not have DynamoDB or want a Free Tier friendly setup, run the bootstrap with DynamoDB disabled (default):

```bash
cd infra/eks-terraform/backend-bootstrap
terraform init
terraform apply -var="aws_region=us-east-1" -var="create_dynamodb=false"
```

This will create only the S3 bucket. Without DynamoDB you will not have state locking; avoid running concurrent `terraform apply` operations.
