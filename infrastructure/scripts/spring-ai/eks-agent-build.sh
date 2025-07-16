#!/bin/bash
# eks-agent-build.sh - Script to connect to ECR, build and push image

set -e

echo "Starting build process for Spring AI Agent..."

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
