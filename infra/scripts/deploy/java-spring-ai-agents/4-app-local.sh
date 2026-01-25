#!/bin/bash

# AI Agent Local Run - Start application locally with full security, MCP, and database
# Requires: 1-mcp-server.sh (MCP server on EKS), 2-cognito.sh (Cognito), 3-app.sh (application)

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

APP_DIR=~/environment/aiagent

log_info "Starting AI Agent locally with full configuration..."
log_info "AWS Account: ${ACCOUNT_ID}"
log_info "AWS Region: ${AWS_REGION}"

# ============================================================================
# Get MCP Server URL from EKS
# ============================================================================
log_info "Getting MCP Server URL from EKS..."
MCP_URL=http://$(kubectl get ingress mcpserver -n mcpserver \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

if [[ -z "${MCP_URL}" || "${MCP_URL}" == "http://" ]]; then
    log_error "MCP Server not found on EKS. Run 1-mcp-server.sh first."
    exit 1
fi

# Verify MCP server is accessible
if ! curl -s --max-time 5 ${MCP_URL} > /dev/null 2>&1; then
    log_error "MCP Server at ${MCP_URL} is not responding"
    exit 1
fi
log_success "MCP Server URL: ${MCP_URL}"

# ============================================================================
# Get Cognito configuration
# ============================================================================
log_info "Getting Cognito configuration..."
USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
  --query "UserPools[?Name=='aiagent-user-pool'].Id | [0]" --output text 2>/dev/null || echo "")

if [[ -z "${USER_POOL_ID}" || "${USER_POOL_ID}" == "None" ]]; then
    log_error "Cognito User Pool not found. Run 2-cognito.sh first."
    exit 1
fi

COGNITO_ISSUER_URI="https://cognito-idp.${AWS_REGION}.amazonaws.com/${USER_POOL_ID}"
log_success "Cognito Issuer URI: ${COGNITO_ISSUER_URI}"

# ============================================================================
# Get database credentials
# ============================================================================
log_info "Getting database credentials..."
SPRING_DATASOURCE_URL=$(aws ssm get-parameter --name workshop-db-connection-string --no-cli-pager \
  | jq --raw-output '.Parameter.Value')
SPRING_DATASOURCE_USERNAME=$(aws secretsmanager get-secret-value --secret-id workshop-db-secret --no-cli-pager \
  | jq --raw-output '.SecretString' | jq -r .username)
SPRING_DATASOURCE_PASSWORD=$(aws secretsmanager get-secret-value --secret-id workshop-db-secret --no-cli-pager \
  | jq --raw-output '.SecretString' | jq -r .password)
log_success "Database credentials retrieved"

# ============================================================================
# Verify application exists
# ============================================================================
if [[ ! -d "${APP_DIR}" ]]; then
    log_error "AI Agent application not found at ${APP_DIR}. Run 3-app.sh first."
    exit 1
fi

# ============================================================================
# Start the application
# ============================================================================
log_info "Starting AI Agent application..."
log_info "Configuration:"
echo "  MCP Server: ${MCP_URL}"
echo "  Cognito: ${COGNITO_ISSUER_URI}"
echo "  Database: ${SPRING_DATASOURCE_URL}"

cd ${APP_DIR}

export SPRING_DATASOURCE_URL
export SPRING_DATASOURCE_USERNAME
export SPRING_DATASOURCE_PASSWORD
export COGNITO_ISSUER_URI
export SPRING_AI_MCP_CLIENT_STREAMABLEHTTP_CONNECTIONS_SERVER1_URL=${MCP_URL}

log_info "Running: ./mvnw spring-boot:run"
./mvnw spring-boot:run
