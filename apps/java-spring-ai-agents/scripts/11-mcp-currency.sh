#!/bin/bash
set -e

echo "=============================================="
echo "11-mcp-currency.sh - Currency Lambda Gateway Target"
echo "=============================================="

# Check if .envrc exists
if [ ! -f ~/environment/.envrc ]; then
    echo "Error: ~/environment/.envrc not found. Run previous scripts first."
    exit 1
fi

# Source existing environment
source ~/environment/.envrc 2>/dev/null || true

# Verify required variables
if [ -z "${GATEWAY_ID}" ]; then
    echo "Error: Missing GATEWAY_ID. Run 06-mcp-gateway.sh first."
    exit 1
fi

# Get account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
AWS_REGION=$(aws configure get region)

echo "Account: ${ACCOUNT_ID}"
echo "Region: ${AWS_REGION}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

## Creating the IAM role

echo ""
echo "## Deploying the currency converter Lambda"
echo "1. Create the IAM role"

# Check if role exists
if aws iam get-role --role-name "mcp-currency-role" --no-cli-pager >/dev/null 2>&1; then
    echo "IAM role already exists: mcp-currency-role"
else
    echo "Creating IAM role: mcp-currency-role"

    aws iam create-role \
        --role-name "mcp-currency-role" \
        --permissions-boundary "arn:aws:iam::${ACCOUNT_ID}:policy/workshop-boundary" \
        --assume-role-policy-document '{
            "Version": "2012-10-17",
            "Statement": [{
                "Effect": "Allow",
                "Principal": {"Service": "lambda.amazonaws.com"},
                "Action": "sts:AssumeRole"
            }]
        }' \
        --no-cli-pager

    aws iam attach-role-policy \
        --role-name "mcp-currency-role" \
        --policy-arn arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole \
        --no-cli-pager

    echo "Waiting for role propagation..."
    sleep 10
fi

## Building the Lambda package

echo ""
echo "2. Build the Lambda package"

cd "${SCRIPT_DIR}/../currency"
mvn clean package -DskipTests -ntp

## Deploying the Lambda function

echo ""
echo "3. Deploy the Lambda function"

# Check if function exists
FUNCTION_EXISTS=$(aws lambda get-function --function-name "mcp-currency" \
    --region ${AWS_REGION} --no-cli-pager 2>/dev/null || echo "")

JAR_FILE=$(ls "${SCRIPT_DIR}/../currency/target"/*.jar | head -1)

if [ -n "${FUNCTION_EXISTS}" ]; then
    echo "Lambda function already exists, updating code..."
    aws lambda update-function-code \
        --function-name "mcp-currency" \
        --zip-file "fileb://${JAR_FILE}" \
        --region ${AWS_REGION} \
        --no-cli-pager
else
    echo "Creating Lambda function: mcp-currency"
    aws lambda create-function \
        --function-name "mcp-currency" \
        --runtime java25 \
        --role "arn:aws:iam::${ACCOUNT_ID}:role/mcp-currency-role" \
        --handler "com.example.currency.CurrencyHandler::handleRequest" \
        --zip-file "fileb://${JAR_FILE}" \
        --timeout 30 \
        --memory-size 512 \
        --region ${AWS_REGION} \
        --no-cli-pager
fi

aws lambda wait function-active-v2 \
    --function-name "mcp-currency" \
    --region ${AWS_REGION} \
    --no-cli-pager
echo "Lambda ready: mcp-currency"

## Adding Lambda invoke permission to Gateway role

echo ""
echo "4. Add Lambda invoke permission to Gateway role"

aws iam put-role-policy \
    --role-name "mcp-gateway-role" \
    --policy-name "CurrencyLambdaInvoke" \
    --policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [{
            \"Effect\": \"Allow\",
            \"Action\": \"lambda:InvokeFunction\",
            \"Resource\": \"arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:mcp-currency\"
        }]
    }" \
    --no-cli-pager

sleep 10

## Creating the Gateway target

echo ""
echo "5. Create the Gateway target"

# Check if target already exists
EXISTING_TARGET=$(aws bedrock-agentcore-control list-gateway-targets \
    --gateway-identifier "${GATEWAY_ID}" --region ${AWS_REGION} --no-cli-pager \
    --query "items[?name=='currency'].targetId | [0]" --output text 2>/dev/null || echo "None")

if [ "${EXISTING_TARGET}" != "None" ] && [ -n "${EXISTING_TARGET}" ]; then
    echo "Currency target already exists"
else
    echo "Creating currency target"

    LAMBDA_TOOLS='[
      {
        "name": "convertCurrency",
        "description": "Convert amount between currencies using real-time exchange rates",
        "inputSchema": {
          "type": "object",
          "properties": {
            "fromCurrency": {"type": "string", "description": "Source currency code (USD, EUR, GBP, etc.)"},
            "toCurrency": {"type": "string", "description": "Target currency code"},
            "amount": {"type": "number", "description": "Amount to convert"}
          },
          "required": ["fromCurrency", "toCurrency", "amount"]
        }
      },
      {
        "name": "getSupportedCurrencies",
        "description": "Get list of all supported currency codes for conversion",
        "inputSchema": {"type": "object", "properties": {}}
      }
    ]'

    TARGET_CONFIG=$(jq -n \
        --arg arn "arn:aws:lambda:${AWS_REGION}:${ACCOUNT_ID}:function:mcp-currency" \
        --argjson tools "${LAMBDA_TOOLS}" \
        '{mcp: {lambda: {lambdaArn: $arn, toolSchema: {inlinePayload: $tools}}}}')

    aws bedrock-agentcore-control create-gateway-target \
        --gateway-identifier "${GATEWAY_ID}" \
        --name "currency" \
        --target-configuration "${TARGET_CONFIG}" \
        --credential-provider-configurations '[{"credentialProviderType":"GATEWAY_IAM_ROLE"}]' \
        --region ${AWS_REGION} \
        --no-cli-pager
fi

## Waiting for target to be ready

echo ""
echo "6. Wait for target to be ready"

TARGET_ID=$(aws bedrock-agentcore-control list-gateway-targets \
    --gateway-identifier "${GATEWAY_ID}" --region ${AWS_REGION} --no-cli-pager \
    --query "items[?name=='currency'].targetId | [0]" --output text)

echo -n "Waiting for currency target"
while [ "$(aws bedrock-agentcore-control get-gateway-target \
    --gateway-identifier "${GATEWAY_ID}" --target-id "${TARGET_ID}" \
    --region ${AWS_REGION} --no-cli-pager \
    --query 'status' --output text)" != "READY" ]; do
    echo -n "."; sleep 5
done && echo " READY"

echo ""
echo "=============================================="
echo "Currency Lambda Gateway target complete!"
echo "=============================================="
