#!/bin/bash
# eks-agent-deploy.sh - Script to connect to ECR, build and push image, restart deployment, and show logs

set -e

echo "Starting deployment process for Spring AI Agent..."

# Login to ECR
echo "Logging in to Amazon ECR..."
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ECR_URI

# Navigate to project directory
echo "Navigating to project directory..."
cd ~/environment/unicorn-spring-ai-agent || {
  echo "Error: Project directory not found. Exiting."
  exit 1
}

# Build and push container image
echo "Building container image..."
mvn spring-boot:build-image -DskipTests -Dspring-boot.build-image.imageName=$ECR_URI:latest

echo "Pushing container image to ECR..."
docker push $ECR_URI:latest

# Restart deployment by applying a rolling update
echo "Restarting deployment..."
kubectl rollout restart deployment unicorn-spring-ai-agent -n unicorn-spring-ai-agent

# Wait for pods to be ready
echo "Waiting for pods to be ready..."
kubectl rollout status deployment unicorn-spring-ai-agent -n unicorn-spring-ai-agent --timeout=300s

# Get the pod name
POD_NAME=$(kubectl get pods -n unicorn-spring-ai-agent -l app=unicorn-spring-ai-agent -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
  echo "Error: Could not find pod. Exiting."
  exit 1
fi

# Show logs
echo "Showing logs from pod $POD_NAME..."
kubectl logs -f $POD_NAME -n unicorn-spring-ai-agent

echo "Deployment process completed successfully!"
