#!/bin/bash
set -e

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Use a single variable for app name, repository, service, and cluster
APP_NAME="workshop-app"

echo "Building and pushing Docker image to ECR in region $AWS_REGION"

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Change to the script directory where Dockerfile is located
cd "$SCRIPT_DIR"

# Build the Docker image
docker build -t $APP_NAME -f Dockerfile .

# Tag the image
docker tag $APP_NAME:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME:latest

# Push the image to ECR
docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME:latest

echo "Image successfully pushed to $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME:latest"

# Restart ECS deployment by forcing a new deployment
echo "Restarting ECS deployment for service $APP_NAME in cluster $APP_NAME"
aws ecs update-service --cluster $APP_NAME --service $APP_NAME --force-new-deployment --region $AWS_REGION --no-cli-pager

echo "ECS deployment restarted successfully"
