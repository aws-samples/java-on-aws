variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "demo-eks-cluster"
}

variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.large"
}

variable "node_desired_count" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 1
}

variable "k8s_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.28"
}
