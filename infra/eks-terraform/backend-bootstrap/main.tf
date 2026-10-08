terraform {
  required_version = ">= 1.0.0"
}

provider "aws" {
  region = var.aws_region
}

resource "random_id" "suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "tfstate" {
  bucket = "tfstate-${var.project_name}-${random_id.suffix.hex}"
  force_destroy = true
  tags = {
    Name = "tfstate-${var.project_name}"
  }
}

resource "aws_s3_bucket_acl" "tfstate_acl" {
  bucket = aws_s3_bucket.tfstate.id
  acl    = "private"
}

resource "aws_dynamodb_table" "tf_locks" {
  count        = var.create_dynamodb ? 1 : 0
  name         = "tf-locks-${var.project_name}-${random_id.suffix.hex}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"
  attribute {
    name = "LockID"
    type = "S"
  }
  tags = { Name = "tf-locks-${var.project_name}" }
}

output "bucket" {
  value = aws_s3_bucket.tfstate.bucket
}

output "dynamodb_table" {
  value = try(aws_dynamodb_table.tf_locks[0].name, "")
}
