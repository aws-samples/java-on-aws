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
cp -r ~/java-on-aws/apps/unicorn-store-spring-java25 ~/environment/unicorn-store-spring
log_success "Copied unicorn-store-spring (Java 25) to ~/environment"

# Configure global git user
log_info "Configuring global git user..."
git config --global user.name "Workshop User"
git config --global user.email "user@sample.com"
log_success "Git user configured: Workshop User <user@sample.com>"

# Initialize git repository in unicorn-store-spring
log_info "Initializing git repository in unicorn-store-spring..."
cd ~/environment/unicorn-store-spring
git init -b main
git add .
git commit -m "Initial commit"
log_success "Git repository initialized with initial commit"

# Change to the app directory
cd ~/environment/unicorn-store-spring

# Build the application with Maven
log_info "Building application with Maven..."
mvn clean package -ntp
log_success "Maven build completed"

# Login to ECR
log_info "Logging in to ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"
log_success "ECR login successful"

# Build Docker image
log_info "Building Docker image..."
docker build -t "$IMAGE_NAME" .
log_success "Docker image built"

# Delete local Docker images to free up space
log_info "Cleaning up local Docker images..."
docker rmi "$IMAGE_NAME" 2>/dev/null || true
docker image prune -f
log_success "Local Docker images cleaned up"

# Emit for bootstrap summary
echo "✅ Success: Unicorn Store Spring Setup"
