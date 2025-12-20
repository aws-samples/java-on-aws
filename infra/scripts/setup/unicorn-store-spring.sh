#!/bin/bash

# Unicorn Store Spring - Build and push Docker image to ECR
# Copies app from cloned repo, builds Docker image, and pushes to ECR with tags

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

log_info "Setting up Unicorn Store Spring application..."

# Get AWS account and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_NAME="unicorn-store-spring"

log_info "AWS Account: $AWS_ACCOUNT_ID"
log_info "AWS Region: $AWS_REGION"
log_info "ECR Registry: $ECR_REGISTRY"

# Copy unicorn-store-spring to ~/environment
log_info "Copying unicorn-store-spring to ~/environment..."
if [ -d ~/environment/unicorn-store-spring ]; then
    log_warning "~/environment/unicorn-store-spring already exists, removing..."
    rm -rf ~/environment/unicorn-store-spring
fi
cp -r ~/java-on-aws/apps/unicorn-store-spring ~/environment/

# Remove test directory to avoid testcontainers issues during Docker build
rm -rf ~/environment/unicorn-store-spring/src/test
log_success "Copied unicorn-store-spring to ~/environment (tests removed)"

# Change to the app directory
cd ~/environment/unicorn-store-spring

# Login to ECR
log_info "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
log_success "ECR login successful"

# Build Docker image
log_info "Building Docker image..."
docker build -t "$IMAGE_NAME" .
log_success "Docker image built"

# Tag and push with 'initial' tag
log_info "Tagging and pushing image with 'initial' tag..."
docker tag "$IMAGE_NAME:latest" "$ECR_REGISTRY/$IMAGE_NAME:initial"
docker push "$ECR_REGISTRY/$IMAGE_NAME:initial"
log_success "Pushed $ECR_REGISTRY/$IMAGE_NAME:initial"

# Tag and push with 'latest' tag
log_info "Tagging and pushing image with 'latest' tag..."
docker tag "$IMAGE_NAME:latest" "$ECR_REGISTRY/$IMAGE_NAME:latest"
docker push "$ECR_REGISTRY/$IMAGE_NAME:latest"
log_success "Pushed $ECR_REGISTRY/$IMAGE_NAME:latest"

log_success "Unicorn Store Spring setup completed"

# Emit for bootstrap summary
echo "✅ Success: Unicorn Store Spring (ECR: $IMAGE_NAME:initial, $IMAGE_NAME:latest)"
