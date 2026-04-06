#!/bin/bash
set -e

echo "=============================================="
echo "01-setup.sh - Environment Setup"
echo "=============================================="

## Creating the environment directory

echo ""
echo "## Setting up environment"
echo "1. Create environment directory and .envrc file"

mkdir -p ~/environment

if [ -f ~/environment/.envrc ]; then
    echo "Environment file already exists: ~/environment/.envrc"
else
    echo "Creating environment file: ~/environment/.envrc"
    touch ~/environment/.envrc
fi

## Copying application code

echo ""
echo "2. Copy application code to ~/environment"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -d ~/environment/aiagent ]; then
    echo "aiagent already exists in ~/environment"
else
    echo "Copying aiagent..."
    cp -r "${SCRIPT_DIR}/../aiagent" ~/environment/aiagent
fi

if [ -d ~/environment/backoffice ]; then
    echo "backoffice already exists in ~/environment"
else
    echo "Copying backoffice (trip base)..."
    cp -r "${SCRIPT_DIR}/../backoffice/trip" ~/environment/backoffice

    echo "Adding expense package..."
    cp -r "${SCRIPT_DIR}/../backoffice/expense" \
        ~/environment/backoffice/src/main/java/com/example/backoffice/expense

    echo "Adding TripTools.java..."
    cp "${SCRIPT_DIR}/../backoffice/tools/TripTools.java" \
        ~/environment/backoffice/src/main/java/com/example/backoffice/trip/TripTools.java

    echo "Adding ExpenseTools.java..."
    cp "${SCRIPT_DIR}/../backoffice/tools/ExpenseTools.java" \
        ~/environment/backoffice/src/main/java/com/example/backoffice/expense/ExpenseTools.java

    echo "Updating pom.xml with tools dependencies..."
    cp "${SCRIPT_DIR}/../backoffice/tools/pom.xml" ~/environment/backoffice/pom.xml

    echo "Updating application.properties with MCP server config..."
    cp "${SCRIPT_DIR}/../backoffice/tools/application.properties" \
        ~/environment/backoffice/src/main/resources/application.properties
fi

# Create DynamoDB tables for backoffice
if aws dynamodb describe-table --table-name "backoffice-trip" --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1; then
    echo "DynamoDB table backoffice-trip already exists"
else
    echo "Creating DynamoDB table: backoffice-trip"
    aws dynamodb create-table \
        --table-name "backoffice-trip" \
        --attribute-definitions \
            AttributeName=pk,AttributeType=S \
            AttributeName=sk,AttributeType=S \
            AttributeName=tripReference,AttributeType=S \
        --key-schema AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE \
        --global-secondary-indexes \
            "IndexName=tripReference-index,KeySchema=[{AttributeName=tripReference,KeyType=HASH}],Projection={ProjectionType=ALL}" \
        --billing-mode PAY_PER_REQUEST \
        --region ${AWS_REGION} \
        --no-cli-pager
    aws dynamodb wait table-exists --table-name "backoffice-trip" --region ${AWS_REGION}
    echo "Table created: backoffice-trip"
fi

if aws dynamodb describe-table --table-name "backoffice-expense" --region ${AWS_REGION} --no-cli-pager >/dev/null 2>&1; then
    echo "DynamoDB table backoffice-expense already exists"
else
    echo "Creating DynamoDB table: backoffice-expense"
    aws dynamodb create-table \
        --table-name "backoffice-expense" \
        --attribute-definitions \
            AttributeName=pk,AttributeType=S \
            AttributeName=sk,AttributeType=S \
            AttributeName=expenseReference,AttributeType=S \
            AttributeName=tripReference,AttributeType=S \
        --key-schema AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE \
        --global-secondary-indexes \
            "IndexName=expenseReference-index,KeySchema=[{AttributeName=expenseReference,KeyType=HASH}],Projection={ProjectionType=ALL}" \
            "IndexName=tripReference-index,KeySchema=[{AttributeName=tripReference,KeyType=HASH}],Projection={ProjectionType=ALL}" \
        --billing-mode PAY_PER_REQUEST \
        --region ${AWS_REGION} \
        --no-cli-pager
    aws dynamodb wait table-exists --table-name "backoffice-expense" --region ${AWS_REGION}
    echo "Table created: backoffice-expense"
fi

# Verify required environment variables
if [ -z "${AWS_REGION}" ]; then
    echo "Error: AWS_REGION is not set"
    exit 1
fi
if [ -z "${ACCOUNT_ID}" ]; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
fi

echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"

## Setting up direnv

echo ""
echo "3. Configure direnv"

if command -v direnv &> /dev/null; then
    cd ~/environment
    direnv allow .
    echo "direnv configured"
else
    echo "Warning: direnv not installed. You'll need to source .envrc manually."
fi

echo ""
echo "=============================================="
echo "Environment setup complete!"
echo "=============================================="
echo ""
echo "Environment file: ~/environment/.envrc"
echo "AWS_REGION=${AWS_REGION}"
echo "ACCOUNT_ID=${ACCOUNT_ID}"
echo ""
echo "Next: Run 02-memory.sh to create AgentCore Memory"
