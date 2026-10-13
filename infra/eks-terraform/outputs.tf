output "cluster_name" {
  value = aws_eks_cluster.this.name
}

output "kubeconfig_certificate_authority_data" {
  value     = aws_eks_cluster.this.certificate_authority[0].data
  sensitive = true
}

output "kubeconfig_endpoint" {
  value = aws_eks_cluster.this.endpoint
}
