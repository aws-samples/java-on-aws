#!/bin/bash

# Unicorn Store Spring - Build and push Docker image to ECR
# Copies app from cloned repo, builds Docker image, and pushes to ECR with tags

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

log_info "Setting up Unicorn Store Spring application..."

ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
IMAGE_NAME="unicorn-store-spring"

log_info "AWS Account: $ACCOUNT_ID"
log_info "AWS Region: $AWS_REGION"
log_info "ECR Registry: $ECR_REGISTRY"

# Copy unicorn-store-spring (Java 25 version) to ~/environment
log_info "Copying unicorn-store-spring (Java 25) to ~/environment..."
if [ -d ~/environment/unicorn-store-spring ]; then
    log_warning "~/environment/unicorn-store-spring already exists, removing..."
    rm -rf ~/environment/unicorn-store-spring
fi
cp -r ~/java-on-aws/apps/java25/unicorn-store-spring ~/environment/
log_success "Copied unicorn-store-spring (Java 25) to ~/environment"

# Copy dockerfiles (Java 25 version) to ~/environment
log_info "Copying dockerfiles (Java 25) to ~/environment..."
if [ -d ~/environment/dockerfiles ]; then
    log_warning "~/environment/dockerfiles already exists, removing..."
    rm -rf ~/environment/dockerfiles
fi
cp -r ~/java-on-aws/apps/java25/dockerfiles ~/environment/
log_success "Copied dockerfiles (Java 25) to ~/environment"

# Copy jvm-ai-analyzer to ~/environment
log_info "Copying jvm-ai-analyzer to ~/environment..."
if [ -d ~/environment/jvm-ai-analyzer ]; then
    log_warning "~/environment/jvm-ai-analyzer already exists, removing..."
    rm -rf ~/environment/jvm-ai-analyzer
fi
cp -r ~/java-on-aws/apps/java25/jvm-ai-analyzer ~/environment/
log_success "Copied jvm-ai-analyzer to ~/environment"

# Change to the app directory
cd ~/environment/unicorn-store-spring

# Build the application with Maven
log_info "Building application with Maven..."
mvn clean package -DskipTests -ntp
log_success "Maven build completed"

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
