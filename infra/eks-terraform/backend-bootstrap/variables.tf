variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "project_name" {
  type    = string
  default = "java-on-aws-eks"
}

variable "create_dynamodb" {
  description = "Whether to create a DynamoDB table for state locking. Set to false for Free Tier / no DynamoDB support."
  type        = bool
  default     = false
}
