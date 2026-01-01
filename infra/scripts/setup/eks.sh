#!/bin/bash

# EKS cluster post-deployment setup script
# This script configures the EKS cluster after CDK deployment

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"
source "$SCRIPT_DIR/../lib/wait-for-resources.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

PREFIX="${PREFIX:-workshop}"
CLUSTER_NAME="${PREFIX}-eks"

log_info "Starting EKS cluster setup for cluster: $CLUSTER_NAME"
log_info "Region: $AWS_REGION, Account: $ACCOUNT_ID, Prefix: $PREFIX"

# Wait for EKS cluster to be active
log_info "Waiting for EKS cluster to be ready..."
wait_for_eks_cluster "$CLUSTER_NAME"

log_info "Updating kubeconfig for cluster $CLUSTER_NAME..."
while ! aws eks --region "$AWS_REGION" update-kubeconfig --name "$CLUSTER_NAME"; do
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

# Deploy workshop NodePool (AMD, 4+ vCPU, 16+ GB RAM)
log_info "Deploying workshop NodePool..."
cat <<EOF | kubectl apply -f -
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: workshop
spec:
  template:
    spec:
      nodeClassRef:
        group: eks.amazonaws.com
        kind: NodeClass
        name: default
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: eks.amazonaws.com/instance-cpu-manufacturer
          operator: In
          values: ["amd"]
        - key: eks.amazonaws.com/instance-cpu
          operator: Gt
          values: ["3"]
        - key: eks.amazonaws.com/instance-memory
          operator: Gt
          values: ["16383"]
        - key: eks.amazonaws.com/instance-category
          operator: In
          values: ["c", "m"]
        - key: eks.amazonaws.com/instance-generation
          operator: Gt
          values: ["5"]
  limits:
    cpu: 16
    memory: 64Gi
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
EOF

if [ $? -eq 0 ]; then
    log_success "Workshop NodePool deployed successfully"
else
    log_error "Failed to deploy workshop NodePool"
    exit 1
fi

# Verify EKS add-ons are installed and fully ready
log_info "Verifying EKS add-ons..."

# Check and wait for AWS Secrets Store CSI Driver
if kubectl get daemonset -n aws-secrets-manager secrets-store-csi-driver >/dev/null 2>&1; then
    log_info "Waiting for Secrets Store CSI Driver to be fully ready..."
    kubectl rollout status daemonset/secrets-store-csi-driver -n aws-secrets-manager --timeout=120s
    log_success "AWS Secrets Store CSI Driver is ready"
else
    log_warning "AWS Secrets Store CSI Driver not found"
fi

# Check and wait for AWS Mountpoint S3 CSI Driver
if kubectl get daemonset -n kube-system s3-csi-node >/dev/null 2>&1; then
    log_info "Waiting for S3 CSI Driver to be fully ready..."
    kubectl rollout status daemonset/s3-csi-node -n kube-system --timeout=120s
    log_success "AWS Mountpoint S3 CSI Driver is ready"
else
    log_warning "AWS Mountpoint S3 CSI Driver not found"
fi

# Check and wait for EKS Pod Identity Agent
if kubectl get daemonset -n kube-system eks-pod-identity-agent >/dev/null 2>&1; then
    log_info "Waiting for Pod Identity Agent to be fully ready..."
    kubectl rollout status daemonset/eks-pod-identity-agent -n kube-system --timeout=120s
    log_success "EKS Pod Identity Agent is ready"
else
    log_warning "EKS Pod Identity Agent not found"
fi

# Check and wait for AWS Load Balancer Controller
if kubectl get deployment -n kube-system aws-load-balancer-controller >/dev/null 2>&1; then
    log_info "Waiting for AWS Load Balancer Controller to be fully ready..."
    kubectl rollout status deployment/aws-load-balancer-controller -n kube-system --timeout=120s
    log_success "AWS Load Balancer Controller is ready"
else
    log_warning "AWS Load Balancer Controller not found"
fi

# Display cluster information
log_info "EKS cluster setup completed successfully!"
log_info "Cluster information:"
echo "  Cluster Name: $CLUSTER_NAME"
echo "  Region: $AWS_REGION"
echo "  Account: $ACCOUNT_ID"

log_info "Checking cluster status..."
kubectl get nodes
kubectl get pods -A | head -10

log_success "EKS cluster setup is complete and ready for workshop use!"

# Emit for bootstrap summary
echo "✅ Success: EKS cluster ($CLUSTER_NAME)"