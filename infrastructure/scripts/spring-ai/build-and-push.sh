#!/bin/bash
set -e

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

# Function to build and push Docker image to ECR
build_and_push_image() {
    local app_name=$1
    local dockerfile_path=$2
    local build_context=$3

    echo "Building and pushing Docker image '$app_name' to ECR in region $AWS_REGION"

    # Check if ECR repository exists, if not sleep and retry
    while true; do
        echo "Checking if ECR repository $app_name exists..."
        if aws ecr describe-repositories --repository-names $app_name --region $AWS_REGION &> /dev/null; then
            echo "ECR repository $app_name exists."
            break
        else
            echo "ECR repository $app_name does not exist. Sleeping for 10 seconds..."
            sleep 10
        fi
    done

    # Login to ECR (only need to do this once)
    if [ "$ECR_LOGIN_DONE" != "true" ]; then
        echo "Logging in to ECR..."
        aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
        ECR_LOGIN_DONE="true"
    fi

    # Build the Docker image
    echo "Building Docker image: $app_name"
    docker build -t $app_name -f "$dockerfile_path" "$build_context"

    # Tag the image
    echo "Tagging image: $app_name:latest -> $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$app_name:latest"
    docker tag $app_name:latest $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$app_name:latest

    # Push the image to ECR
    echo "Pushing image to ECR..."
    docker push $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$app_name:latest

    echo "Image successfully pushed to $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$app_name:latest"
    echo "------------------------------------------------------------"
}

# Process command line arguments
APP_NAME=$1
DOCKERFILE_PATH=$2

# Check if APP_NAME was provided
if [ -z "$APP_NAME" ]; then
    echo "Error: APP_NAME is required as the first argument"
    echo "Usage: $0 <app-name> [dockerfile-path]"
    echo "Example: $0 unicorn-spring-ai-agent ./Dockerfile"
    exit 1
fi

# Check if a Dockerfile path was provided as an argument
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

# Initialize ECR login flag
ECR_LOGIN_DONE="false"

# Build and push the image
build_and_push_image "$APP_NAME" "$DOCKERFILE_PATH" "$BUILD_CONTEXT"
