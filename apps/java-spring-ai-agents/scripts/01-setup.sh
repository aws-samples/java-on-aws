#!/bin/bash
set -e

echo "=============================================="
echo "01-setup.sh - Environment Setup"
echo "=============================================="

# Get account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
AWS_REGION=$(aws configure get region)

echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"

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
fi

# Add basic variables if not present
if ! grep -q "AWS_REGION=" ~/environment/.envrc 2>/dev/null; then
    echo "export AWS_REGION=${AWS_REGION}" >> ~/environment/.envrc
fi

if ! grep -q "ACCOUNT_ID=" ~/environment/.envrc 2>/dev/null; then
    echo "export ACCOUNT_ID=${ACCOUNT_ID}" >> ~/environment/.envrc
fi

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
