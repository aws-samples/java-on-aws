#!/bin/bash
# eks-agent-deploy.sh - Script to connect to ECR, build and push image, restart deployment, and show logs

set -e

echo "Starting deployment process for Spring AI Agent..."

# Get ECR URI - exit if not found
echo "Getting ECR URI..."
if ! ECR_URI=$(aws ecr describe-repositories --repository-names unicorn-spring-ai-agent | jq --raw-output '.repositories[0].repositoryUri' 2>/dev/null); then
  echo "Error: Could not get ECR URI. Repository 'unicorn-spring-ai-agent' may not exist. Exiting."
  exit 1
else
  echo "ECR URI: $ECR_URI"
fi

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

# Get the name of a running pod
echo "Finding running pod..."
POD_NAME=$(kubectl get pods -n unicorn-spring-ai-agent -l app=unicorn-spring-ai-agent --field-selector=status.phase=Running -o jsonpath='{.items[0].metadata.name}')
if [ -z "$POD_NAME" ]; then
  echo "Error: Could not find running pod. Retrying with any pod status..."
  POD_NAME=$(kubectl get pods -n unicorn-spring-ai-agent -l app=unicorn-spring-ai-agent -o jsonpath='{.items[0].metadata.name}')
  if [ -z "$POD_NAME" ]; then
    echo "Error: Could not find any pod. Exiting."
    exit 1
  fi
fi
echo "Found pod: $POD_NAME"

# Show logs
echo "Showing logs from pod $POD_NAME..."
kubectl logs -f $POD_NAME -n unicorn-spring-ai-agent

echo "Deployment process completed successfully!"
