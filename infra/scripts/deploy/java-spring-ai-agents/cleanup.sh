#!/bin/bash

# Cleanup - Delete all resources created by scripts 1-8
# Safe order: deployments first, then infrastructure, then source directories

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

log_info "Cleaning up AI Agent workshop resources..."
log_info "AWS Account: ${ACCOUNT_ID}"
log_info "AWS Region: ${AWS_REGION}"

# ============================================================================
# 8-agentcore.sh resources
# ============================================================================
log_info "Cleaning up AgentCore resources..."

# Delete AgentCore Runtime
RUNTIME_ID=$(aws bedrock-agentcore-control list-agent-runtimes --region ${AWS_REGION} --no-cli-pager \
  --query "agentRuntimes[?agentRuntimeName=='aiagent'].agentRuntimeId | [0]" --output text 2>/dev/null || echo "")
if [[ -n "${RUNTIME_ID}" && "${RUNTIME_ID}" != "None" ]]; then
    log_info "Deleting AgentCore Runtime: ${RUNTIME_ID}"
    aws bedrock-agentcore-control delete-agent-runtime \
      --agent-runtime-id "${RUNTIME_ID}" \
      --region ${AWS_REGION} \
      --no-cli-pager 2>/dev/null || true
    log_success "AgentCore Runtime deleted"
fi

# Delete CloudFront distribution and S3 bucket for UI
CF_DIST_ID=$(aws cloudfront list-distributions --no-cli-pager \
  --query "DistributionList.Items[?Comment=='aiagent UI'].Id | [0]" --output text 2>/dev/null || echo "")
if [[ -n "${CF_DIST_ID}" && "${CF_DIST_ID}" != "None" ]]; then
    log_info "Disabling CloudFront distribution: ${CF_DIST_ID}"

    # Get current config and disable
    ETAG=$(aws cloudfront get-distribution-config --id "${CF_DIST_ID}" --no-cli-pager \
      --query 'ETag' --output text 2>/dev/null || echo "")
    if [[ -n "${ETAG}" ]]; then
        aws cloudfront get-distribution-config --id "${CF_DIST_ID}" --no-cli-pager \
          --query 'DistributionConfig' > /tmp/cf-config.json 2>/dev/null
        jq '.Enabled = false' /tmp/cf-config.json > /tmp/cf-config-disabled.json
        aws cloudfront update-distribution --id "${CF_DIST_ID}" \
          --distribution-config file:///tmp/cf-config-disabled.json \
          --if-match "${ETAG}" --no-cli-pager 2>/dev/null || true

        log_info "Waiting for CloudFront to be disabled (this may take several minutes)..."
        aws cloudfront wait distribution-deployed --id "${CF_DIST_ID}" 2>/dev/null || true

        ETAG=$(aws cloudfront get-distribution-config --id "${CF_DIST_ID}" --no-cli-pager \
          --query 'ETag' --output text 2>/dev/null || echo "")
        aws cloudfront delete-distribution --id "${CF_DIST_ID}" --if-match "${ETAG}" --no-cli-pager 2>/dev/null || true
        log_success "CloudFront distribution deleted"
    fi
fi

# Delete OAI
OAI_ID=$(aws cloudfront list-cloud-front-origin-access-identities --no-cli-pager \
  --query "CloudFrontOriginAccessIdentityList.Items[?Comment=='OAI for aiagent UI'].Id | [0]" --output text 2>/dev/null || echo "")
if [[ -n "${OAI_ID}" && "${OAI_ID}" != "None" ]]; then
    log_info "Deleting CloudFront OAI: ${OAI_ID}"
    ETAG=$(aws cloudfront get-cloud-front-origin-access-identity --id "${OAI_ID}" --no-cli-pager \
      --query 'ETag' --output text 2>/dev/null || echo "")
    aws cloudfront delete-cloud-front-origin-access-identity --id "${OAI_ID}" --if-match "${ETAG}" --no-cli-pager 2>/dev/null || true
    log_success "CloudFront OAI deleted"
fi

# Delete UI S3 bucket
UI_BUCKET=$(aws s3api list-buckets --no-cli-pager \
  --query "Buckets[?starts_with(Name, 'aiagent-ui-${ACCOUNT_ID}')].Name | [0]" --output text 2>/dev/null || echo "")
if [[ -n "${UI_BUCKET}" && "${UI_BUCKET}" != "None" ]]; then
    log_info "Deleting S3 bucket: ${UI_BUCKET}"
    aws s3 rm "s3://${UI_BUCKET}" --recursive --no-cli-pager 2>/dev/null || true
    aws s3api delete-bucket --bucket "${UI_BUCKET}" --no-cli-pager 2>/dev/null || true
    log_success "S3 bucket deleted"
fi

# ============================================================================
# 7-lambda.sh resources
# ============================================================================
log_info "Cleaning up Lambda resources..."

# Delete Lambda function
if aws lambda get-function --function-name aiagent --no-cli-pager 2>/dev/null; then
    log_info "Deleting Lambda function: aiagent"
    aws lambda delete-function-url-config --function-name aiagent --no-cli-pager 2>/dev/null || true
    aws lambda delete-function --function-name aiagent --no-cli-pager 2>/dev/null || true
    log_success "Lambda function deleted"
fi

# Delete Lambda security group
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=workshop-vpc" \
  --query 'Vpcs[0].VpcId' --output text --no-cli-pager 2>/dev/null || echo "")
if [[ -n "${VPC_ID}" && "${VPC_ID}" != "None" ]]; then
    SG_ID=$(aws ec2 describe-security-groups \
      --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=aiagent-lambda-sg" \
      --query 'SecurityGroups[0].GroupId' --output text --no-cli-pager 2>/dev/null || echo "")
    if [[ -n "${SG_ID}" && "${SG_ID}" != "None" ]]; then
        log_info "Deleting Lambda security group: ${SG_ID}"
        # Wait for ENIs to be deleted
        sleep 30
        aws ec2 delete-security-group --group-id "${SG_ID}" --no-cli-pager 2>/dev/null || true
        log_success "Lambda security group deleted"
    fi
fi

# ============================================================================
# 6-ecs.sh resources (ECS service is pre-created, just reset config)
# ============================================================================
log_info "Resetting ECS service configuration..."
# ECS cluster and service are pre-created by workshop setup, don't delete

# ============================================================================
# 5-eks.sh resources
# ============================================================================
log_info "Cleaning up EKS AI Agent resources..."

# Delete Kubernetes resources
if kubectl get namespace aiagent 2>/dev/null; then
    log_info "Deleting aiagent namespace and resources..."
    kubectl delete ingress aiagent -n aiagent 2>/dev/null || true
    kubectl delete service aiagent -n aiagent 2>/dev/null || true
    kubectl delete deployment aiagent -n aiagent 2>/dev/null || true
    kubectl delete secretproviderclass aiagent-secrets -n aiagent 2>/dev/null || true
    kubectl delete serviceaccount aiagent -n aiagent 2>/dev/null || true
    kubectl delete namespace aiagent 2>/dev/null || true
    log_success "EKS aiagent resources deleted"
fi

# Delete Pod Identity association for aiagent
ASSOCIATION_ID=$(aws eks list-pod-identity-associations --cluster-name workshop-eks --no-cli-pager \
  --query "associations[?namespace=='aiagent'].associationId | [0]" --output text 2>/dev/null || echo "")
if [[ -n "${ASSOCIATION_ID}" && "${ASSOCIATION_ID}" != "None" ]]; then
    log_info "Deleting Pod Identity association for aiagent: ${ASSOCIATION_ID}"
    aws eks delete-pod-identity-association \
      --cluster-name workshop-eks \
      --association-id "${ASSOCIATION_ID}" \
      --no-cli-pager 2>/dev/null || true
    log_success "Pod Identity association deleted"
fi

# ============================================================================
# 2-cognito.sh resources
# ============================================================================
log_info "Cleaning up Cognito resources..."

USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --no-cli-pager \
  --query "UserPools[?Name=='aiagent-user-pool'].Id | [0]" --output text 2>/dev/null || echo "")
if [[ -n "${USER_POOL_ID}" && "${USER_POOL_ID}" != "None" ]]; then
    log_info "Deleting Cognito User Pool: ${USER_POOL_ID}"

    # Delete app client first
    CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id "${USER_POOL_ID}" --no-cli-pager \
      --query "UserPoolClients[?ClientName=='aiagent-client'].ClientId | [0]" --output text 2>/dev/null || echo "")
    if [[ -n "${CLIENT_ID}" && "${CLIENT_ID}" != "None" ]]; then
        aws cognito-idp delete-user-pool-client \
          --user-pool-id "${USER_POOL_ID}" \
          --client-id "${CLIENT_ID}" \
          --no-cli-pager 2>/dev/null || true
    fi

    # Delete user pool
    aws cognito-idp delete-user-pool --user-pool-id "${USER_POOL_ID}" --no-cli-pager 2>/dev/null || true
    log_success "Cognito User Pool deleted"
fi

# ============================================================================
# 1-mcp-server.sh resources
# ============================================================================
log_info "Cleaning up MCP Server resources..."

# Delete Kubernetes resources
if kubectl get namespace mcpserver 2>/dev/null; then
    log_info "Deleting mcpserver namespace and resources..."
    kubectl delete ingress mcpserver -n mcpserver 2>/dev/null || true
    kubectl delete service mcpserver -n mcpserver 2>/dev/null || true
    kubectl delete deployment mcpserver -n mcpserver 2>/dev/null || true
    kubectl delete secretproviderclass mcpserver-secrets -n mcpserver 2>/dev/null || true
    kubectl delete serviceaccount mcpserver -n mcpserver 2>/dev/null || true
    kubectl delete namespace mcpserver 2>/dev/null || true
    log_success "EKS mcpserver resources deleted"
fi

# Delete Pod Identity association for mcpserver
ASSOCIATION_ID=$(aws eks list-pod-identity-associations --cluster-name workshop-eks --no-cli-pager \
  --query "associations[?namespace=='mcpserver'].associationId | [0]" --output text 2>/dev/null || echo "")
if [[ -n "${ASSOCIATION_ID}" && "${ASSOCIATION_ID}" != "None" ]]; then
    log_info "Deleting Pod Identity association for mcpserver: ${ASSOCIATION_ID}"
    aws eks delete-pod-identity-association \
      --cluster-name workshop-eks \
      --association-id "${ASSOCIATION_ID}" \
      --no-cli-pager 2>/dev/null || true
    log_success "Pod Identity association deleted"
fi

# ============================================================================
# Local directories (3-app.sh, 1-mcp-server.sh)
# ============================================================================
log_info "Cleaning up local directories..."

if [[ -d ~/environment/aiagent ]]; then
    log_info "Removing ~/environment/aiagent"
    rm -rf ~/environment/aiagent
    log_success "aiagent directory removed"
fi

if [[ -d ~/environment/mcpserver ]]; then
    log_info "Removing ~/environment/mcpserver"
    rm -rf ~/environment/mcpserver
    log_success "mcpserver directory removed"
fi

# ============================================================================
# Wait for ALBs to be deleted
# ============================================================================
log_info "Waiting for ALBs to be fully deleted (this may take a few minutes)..."
sleep 60

log_success "Cleanup completed"
echo "✅ All workshop resources have been cleaned up"
