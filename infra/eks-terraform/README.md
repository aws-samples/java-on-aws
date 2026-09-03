This folder contains Terraform to create an AWS EKS cluster in `us-east-1`.

Important: EKS is not fully covered by AWS Free Tier. The control plane and some data transfer and resource usage will incur charges. Read the notes in `NOTES.md` before running.

Commands:

```bash
export AWS_PROFILE=your-profile
cd infra/eks-terraform
terraform init
terraform plan -var="aws_region=us-east-1"
terraform apply -var="aws_region=us-east-1"
```

Set `AWS_PROFILE` or appropriate environment variables for credentials.

Default worker node instance type: `t3.large` (change with the `node_instance_type` variable).

Remote state (S3) bootstrap
 - You can create an S3 bucket + DynamoDB table to store remote state and enable locking using the `backend-bootstrap` helper in this folder.

Steps:
1. Create backend resources from the `backend-bootstrap` folder:

From repository root:

```bash
cd infra/eks-terraform/backend-bootstrap
terraform init
terraform apply -var="aws_region=us-east-1" -var="create_dynamodb=false"
```

If you are already inside `infra/eks-terraform`:

```bash
cd backend-bootstrap
terraform init
terraform apply -var="aws_region=us-east-1" -var="create_dynamodb=false"
```

2. Note the outputs `bucket` and `dynamodb_table`.

3. Initialize the main EKS terraform with those backend values:

```bash
cd ..
terraform init -backend-config="bucket=YOUR_BUCKET_NAME" -backend-config="key=eks/terraform.tfstate" -backend-config="region=us-east-1" -backend-config="dynamodb_table=YOUR_DYNAMODB_TABLE"
terraform plan -var="aws_region=us-east-1"
```

I cannot take control of your terminal. Run the commands above in your shell. Paste any errors here and I'll help fix them.
