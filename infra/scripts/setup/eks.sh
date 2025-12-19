#!/bin/bash

# EKS cluster post-deployment setup script
# This script configures the EKS cluster after CDK deployment

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/wait-for-resources.sh"

# Configuration
CLUSTER_NAME="workshop-eks"
REGION=${AWS_REGION:-$(aws configure get region)}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

log_info "Starting EKS cluster setup for cluster: $CLUSTER_NAME"
log_info "Region: $REGION, Account: $ACCOUNT_ID"

# Wait for EKS cluster to be active
log_info "Waiting for EKS cluster to be ready..."
wait_for_eks_cluster "$CLUSTER_NAME"

# Update kubeconfig with infinite retry (like original)
log_info "Updating kubeconfig for cluster $CLUSTER_NAME..."
while ! aws eks --region "$REGION" update-kubeconfig --name "$CLUSTER_NAME"; do
    log_warning "Failed to update kubeconfig. Retrying in 10 seconds..."
    sleep 10
done
log_success "Successfully updated kubeconfig"

# Verify kubectl connectivity with infinite retry (like original)
log_info "Verifying kubectl connectivity..."
while ! kubectl get ns >/dev/null 2>&1; do
    log_warning "kubectl connectivity failed. Retrying in 10 seconds..."
    sleep 10
done
log_success "kubectl connectivity verified"

# Deploy GP3 StorageClass (encrypted, default)
log_info "Deploying GP3 StorageClass..."
cat <<EOF | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.eks.amazonaws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
  encrypted: "true"
EOF

if [ $? -eq 0 ]; then
    log_success "GP3 StorageClass deployed successfully"
else
    log_error "Failed to deploy GP3 StorageClass"
    exit 1
fi

# Deploy ALB IngressClass
log_info "Deploying ALB IngressClass..."
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  labels:
    app.kubernetes.io/name: LoadBalancerController
  name: alb
spec:
  controller: eks.amazonaws.com/alb
EOF

if [ $? -eq 0 ]; then
    log_success "ALB IngressClass deployed successfully"
else
    log_error "Failed to deploy ALB IngressClass"
    exit 1
fi

# Create SecretProviderClass for database secrets
log_info "Creating SecretProviderClass for database secrets..."
cat <<EOF | kubectl apply -f -
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: workshop-db-secrets
  namespace: default
spec:
  provider: aws
  parameters:
    objects: |
      - objectName: "workshop-db-secret"
        objectType: "secretsmanager"
        jmesPath:
          - path: "username"
            objectAlias: "db-username"
          - path: "password"
            objectAlias: "db-password"
      - objectName: "workshop-db-connection-string"
        objectType: "ssmparameter"
        objectAlias: "db-connection-string"
  secretObjects:
    - secretName: workshop-db-secret
      type: Opaque
      data:
        - objectName: "db-username"
          key: "DB_USERNAME"
        - objectName: "db-password"
          key: "DB_PASSWORD"
        - objectName: "db-connection-string"
          key: "DB_CONNECTION_STRING"
EOF

if [ $? -eq 0 ]; then
    log_success "SecretProviderClass created successfully"
else
    log_error "Failed to create SecretProviderClass"
    exit 1
fi

# Verify EKS add-ons are installed and functional
log_info "Verifying EKS add-ons..."

# Check AWS Secrets Store CSI Driver
if kubectl get daemonset -n aws-secrets-manager secrets-store-csi-driver >/dev/null 2>&1; then
    log_success "AWS Secrets Store CSI Driver is installed"
else
    log_warning "AWS Secrets Store CSI Driver not found"
fi

# Check AWS Mountpoint S3 CSI Driver
if kubectl get daemonset -n kube-system s3-csi-node >/dev/null 2>&1; then
    log_success "AWS Mountpoint S3 CSI Driver is installed"
else
    log_warning "AWS Mountpoint S3 CSI Driver not found"
fi

# Check EKS Pod Identity Agent
if kubectl get daemonset -n kube-system eks-pod-identity-agent >/dev/null 2>&1; then
    log_success "EKS Pod Identity Agent is installed"
else
    log_warning "EKS Pod Identity Agent not found"
fi

# Display cluster information
log_info "EKS cluster setup completed successfully!"
log_info "Cluster information:"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Region: $REGION"
echo "  Account: $ACCOUNT_ID"

log_info "Checking cluster status..."
kubectl get nodes
kubectl get pods -A | head -10

log_success "EKS cluster setup is complete and ready for workshop use!"

# Emit for bootstrap summary
echo "✅ Success: EKS cluster ($CLUSTER_NAME)"