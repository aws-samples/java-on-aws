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
  acl    = "private"
  force_destroy = true
  tags = {
    Name = "tfstate-${var.project_name}"
  }
}

resource "aws_dynamodb_table" "tf_locks" {
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
  value = aws_dynamodb_table.tf_locks.name
}
