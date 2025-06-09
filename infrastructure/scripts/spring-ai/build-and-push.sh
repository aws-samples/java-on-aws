#!/bin/bash
set -e

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Use a single variable for app name, repository, service, and cluster
APP_NAME="unicorn-spring-ai-agent"

# Check if a Dockerfile path was provided as an argument
DOCKERFILE_PATH="$1"
if [ -z "$DOCKERFILE_PATH" ]; then
    # No path provided, use default Dockerfile in script directory
    DOCKERFILE_PATH="$SCRIPT_DIR/Dockerfile"
    BUILD_CONTEXT="$SCRIPT_DIR"
    echo "Using default Dockerfile at $DOCKERFILE_PATH"
else
    # Use the provided Dockerfile path
    if [ ! -f "$DOCKERFILE_PATH" ]; then
        echo "Error: Dockerfile not found at $DOCKERFILE_PATH"
        exit 1
    fi
    # Use the directory of the provided Dockerfile as build context
    BUILD_CONTEXT="$(dirname "$DOCKERFILE_PATH")"
    echo "Using Dockerfile at $DOCKERFILE_PATH"
fi

echo "Building and pushing Docker image to ECR in region $AWS_REGION"

# Check if ECR repository exists, if not sleep and retry
while true; do
    echo "Checking if ECR repository $APP_NAME exists..."
    if aws ecr describe-repositories --repository-names $APP_NAME --region $AWS_REGION &> /dev/null; then
        echo "ECR repository $APP_NAME exists."
        break
    else
        echo "ECR repository $APP_NAME does not exist. Sleeping for 10 seconds..."
        sleep 10
    fi
done

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build the Docker image
docker build -t $APP_NAME -f "$DOCKERFILE_PATH" "$BUILD_CONTEXT"

# Tag the image
docker tag $APP_NAME:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME:latest

# Push the image to ECR
docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME:latest

echo "Image successfully pushed to $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$APP_NAME:latest"
