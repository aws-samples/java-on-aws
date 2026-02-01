#!/bin/bash
# ============================================================
# 99-cleanup.sh - Remove All Resources
# ============================================================
# Phased cleanup: starts slow deletions first, then fast ones
# ============================================================
set -e

REGION=${AWS_REGION:-us-east-1}
APP_NAME="aiagent"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)

# Resource names
RUNTIME_NAME="${APP_NAME}"
COGNITO_POOL="${APP_NAME}-user-pool"
MEMORY_NAME="${APP_NAME}_memory"
KB_NAME="${APP_NAME}-kb"

echo "🗑️  Removing All Resources"
echo ""
echo "Region: ${REGION}"
echo "Account: ${ACCOUNT_ID}"
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""

if [[ ! ${REPLY} =~ ^[Yy]$ ]]; then
  echo "Cancelled"
  exit 0
fi

# ============================================================
# PHASE 1: Start slow deletions (async)
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 1: Starting slow deletions..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 1a. Disable CloudFront (slowest)
echo ""
echo "1️⃣  Disabling CloudFront distribution..."
CF_DIST_ID=$(aws cloudfront list-distributions --no-cli-pager \
  --query "DistributionList.Items[?Comment=='${APP_NAME} UI'].Id | [0]" --output text 2>/dev/null || echo "")

if [ -n "${CF_DIST_ID}" ] && [ "${CF_DIST_ID}" != "None" ] && [ "${CF_DIST_ID}" != "null" ]; then
  ETAG=$(aws cloudfront get-distribution-config --id "${CF_DIST_ID}" \
    --query 'ETag' --output text --no-cli-pager 2>/dev/null || echo "")
  if [ -n "${ETAG}" ]; then
    CONFIG=$(aws cloudfront get-distribution-config --id "${CF_DIST_ID}" --no-cli-pager 2>/dev/null | \
      jq '.DistributionConfig.Enabled = false | .DistributionConfig')
    aws cloudfront update-distribution --id "${CF_DIST_ID}" --if-match "${ETAG}" \
      --distribution-config "${CONFIG}" --no-cli-pager >/dev/null 2>&1 || true
    echo "   ✓ Disabled (will delete later)"
  fi
else
  echo "   ✓ Not found"
  CF_DIST_ID=""
fi

# 1b. Delete AgentCore Memory (slow)
echo ""
echo "2️⃣  Deleting AgentCore Memory..."
MEMORY_ID=$(aws bedrock-agentcore-control list-memories --region "${REGION}" --no-cli-pager \
  --query "memories[?starts_with(id, '${MEMORY_NAME}')].id | [0]" --output text 2>/dev/null || echo "")

if [ -n "${MEMORY_ID}" ] && [ "${MEMORY_ID}" != "None" ] && [ "${MEMORY_ID}" != "null" ]; then
  aws bedrock-agentcore-control delete-memory --memory-id "${MEMORY_ID}" --region "${REGION}" --no-cli-pager 2>/dev/null || true
  echo "   ✓ Delete initiated: ${MEMORY_ID}"
else
  echo "   ✓ Not found"
  MEMORY_ID=""
fi

# 1c. Delete AI Agent Runtime (slow)
echo ""
echo "3️⃣  Deleting AI Agent Runtime..."
RUNTIME_ID=$(aws bedrock-agentcore-control list-agent-runtimes --region "${REGION}" --no-cli-pager \
  --query "agentRuntimes[?agentRuntimeName=='${RUNTIME_NAME}'].agentRuntimeId | [0]" --output text 2>/dev/null || echo "")

if [ -n "${RUNTIME_ID}" ] && [ "${RUNTIME_ID}" != "None" ] && [ "${RUNTIME_ID}" != "null" ]; then
  aws bedrock-agentcore-control delete-agent-runtime --agent-runtime-id "${RUNTIME_ID}" --region "${REGION}" --no-cli-pager 2>/dev/null || true
  echo "   ✓ Delete initiated: ${RUNTIME_ID}"
else
  echo "   ✓ Not found"
  RUNTIME_ID=""
fi

# 1d. Delete Knowledge Base (slow)
echo ""
echo "4️⃣  Deleting Knowledge Base..."
KB_ID=$(aws bedrock-agent list-knowledge-bases --no-cli-pager \
  --query "knowledgeBaseSummaries[?name=='${KB_NAME}'].knowledgeBaseId | [0]" --output text 2>/dev/null || echo "")

if [ -n "${KB_ID}" ] && [ "${KB_ID}" != "None" ] && [ "${KB_ID}" != "null" ]; then
  DS_IDS=$(aws bedrock-agent list-data-sources --knowledge-base-id "${KB_ID}" --no-cli-pager \
    --query 'dataSourceSummaries[].dataSourceId' --output text 2>/dev/null || echo "")
  for DS_ID in ${DS_IDS}; do
    [ -n "${DS_ID}" ] && [ "${DS_ID}" != "None" ] && \
      aws bedrock-agent delete-data-source --knowledge-base-id "${KB_ID}" --data-source-id "${DS_ID}" --no-cli-pager 2>/dev/null || true
  done
  aws bedrock-agent delete-knowledge-base --knowledge-base-id "${KB_ID}" --no-cli-pager 2>/dev/null || true
  echo "   ✓ Delete initiated: ${KB_ID}"
else
  echo "   ✓ Not found"
  KB_ID=""
fi

# ============================================================
# PHASE 2: Delete fast resources
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 2: Deleting fast resources..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 2a. Cognito User Pool
echo ""
echo "5️⃣  Deleting Cognito User Pool..."

USER_POOL_ID=$(aws cognito-idp list-user-pools --max-results 60 --region "${REGION}" --no-cli-pager \
  --query "UserPools[?Name=='${COGNITO_POOL}'].Id | [0]" --output text 2>/dev/null || echo "")
if [ -n "${USER_POOL_ID}" ] && [ "${USER_POOL_ID}" != "None" ] && [ "${USER_POOL_ID}" != "null" ]; then
  aws cognito-idp delete-user-pool --user-pool-id "${USER_POOL_ID}" --region "${REGION}" --no-cli-pager 2>/dev/null || true
  echo "   ✓ Deleted agent pool: ${USER_POOL_ID}"
else
  echo "   ✓ Agent pool not found"
fi

# 2b. UI S3 buckets
echo ""
echo "6️⃣  Deleting UI buckets..."
UI_BUCKETS=$(aws s3api list-buckets --no-cli-pager \
  --query "Buckets[?starts_with(Name, '${APP_NAME}-ui-${ACCOUNT_ID}')].Name" --output text 2>/dev/null || echo "")
if [ -n "${UI_BUCKETS}" ] && [ "${UI_BUCKETS}" != "None" ]; then
  for UI_BUCKET in ${UI_BUCKETS}; do
    aws s3 rm "s3://${UI_BUCKET}" --recursive --no-cli-pager 2>/dev/null || true
    aws s3api delete-bucket --bucket "${UI_BUCKET}" --no-cli-pager 2>/dev/null || true
    echo "   ✓ Deleted: ${UI_BUCKET}"
  done
else
  echo "   ✓ Not found"
fi

# 2c. KB Data buckets
echo ""
echo "7️⃣  Deleting KB Data buckets..."
KB_DATA_BUCKETS=$(aws s3api list-buckets --no-cli-pager \
  --query "Buckets[?starts_with(Name, '${APP_NAME}-kb-data-${ACCOUNT_ID}')].Name" --output text 2>/dev/null || echo "")
if [ -n "${KB_DATA_BUCKETS}" ] && [ "${KB_DATA_BUCKETS}" != "None" ]; then
  for KB_DATA_BUCKET in ${KB_DATA_BUCKETS}; do
    aws s3 rm "s3://${KB_DATA_BUCKET}" --recursive --no-cli-pager 2>/dev/null || true
    aws s3api delete-bucket --bucket "${KB_DATA_BUCKET}" --no-cli-pager 2>/dev/null || true
    echo "   ✓ Deleted: ${KB_DATA_BUCKET}"
  done
else
  echo "   ✓ Not found"
fi

# 2d. KB Vectors buckets
echo ""
echo "8️⃣  Deleting KB Vectors buckets..."
KB_VECTORS_BUCKETS=$(aws s3vectors list-vector-buckets --no-cli-pager \
  --query "vectorBuckets[?starts_with(vectorBucketName, '${APP_NAME}-kb-vectors')].vectorBucketName" --output text 2>/dev/null || echo "")
if [ -n "${KB_VECTORS_BUCKETS}" ] && [ "${KB_VECTORS_BUCKETS}" != "None" ]; then
  for KB_VECTORS_BUCKET in ${KB_VECTORS_BUCKETS}; do
    # Delete all indexes in the bucket first
    INDEX_NAMES=$(aws s3vectors list-indexes --vector-bucket-name "${KB_VECTORS_BUCKET}" --no-cli-pager \
      --query 'indexes[].indexName' --output text 2>/dev/null || echo "")
    for INDEX_NAME in ${INDEX_NAMES}; do
      [ -n "${INDEX_NAME}" ] && [ "${INDEX_NAME}" != "None" ] && \
        aws s3vectors delete-index --vector-bucket-name "${KB_VECTORS_BUCKET}" --index-name "${INDEX_NAME}" --no-cli-pager 2>/dev/null || true
    done
    # Wait for indexes to be deleted
    for i in {1..30}; do
      REMAINING=$(aws s3vectors list-indexes --vector-bucket-name "${KB_VECTORS_BUCKET}" --no-cli-pager \
        --query 'length(indexes)' --output text 2>/dev/null || echo "0")
      [ "${REMAINING}" = "0" ] || [ "${REMAINING}" = "None" ] && break
      sleep 2
    done
    aws s3vectors delete-vector-bucket --vector-bucket-name "${KB_VECTORS_BUCKET}" --no-cli-pager 2>/dev/null || true
    echo "   ✓ Deleted: ${KB_VECTORS_BUCKET}"
  done
else
  echo "   ✓ Not found"
fi

# 2e. ECR repository
echo ""
echo "9️⃣  Deleting ECR repository..."
aws ecr delete-repository --repository-name "${APP_NAME}" --force --region "${REGION}" --no-cli-pager 2>/dev/null && echo "   ✓ Deleted: ${APP_NAME}" || echo "   ✓ aiagent repo not found"

# 2f. IAM roles
echo ""
echo "🔟 Deleting IAM roles..."

# Helper function to delete role with inline policies
delete_role() {
  local role_name="$1"
  if aws iam get-role --role-name "${role_name}" --no-cli-pager >/dev/null 2>&1; then
    # Delete inline policies
    POLICIES=$(aws iam list-role-policies --role-name "${role_name}" --no-cli-pager \
      --query 'PolicyNames' --output text 2>/dev/null || echo "")
    for policy in ${POLICIES}; do
      aws iam delete-role-policy --role-name "${role_name}" --policy-name "${policy}" --no-cli-pager 2>/dev/null || true
    done
    # Detach managed policies
    ATTACHED=$(aws iam list-attached-role-policies --role-name "${role_name}" --no-cli-pager \
      --query 'AttachedPolicies[].PolicyArn' --output text 2>/dev/null || echo "")
    for arn in ${ATTACHED}; do
      aws iam detach-role-policy --role-name "${role_name}" --policy-arn "${arn}" --no-cli-pager 2>/dev/null || true
    done
    # Delete role
    aws iam delete-role --role-name "${role_name}" --no-cli-pager 2>/dev/null && \
      echo "   ✓ Deleted: ${role_name}" || echo "   ⚠️  Failed to delete: ${role_name}"
  else
    echo "   ✓ Not found: ${role_name}"
  fi
}

delete_role "${APP_NAME}-runtime-role"
delete_role "${APP_NAME}-kb-role"

# 2g. CloudFront OAI
echo ""
echo "[11] Deleting CloudFront OAI..."
OAI_ID=$(aws cloudfront list-cloud-front-origin-access-identities --no-cli-pager \
  --query "CloudFrontOriginAccessIdentityList.Items[?Comment=='OAI for ${APP_NAME} UI'].Id | [0]" --output text 2>/dev/null || echo "")

if [ -n "${OAI_ID}" ] && [ "${OAI_ID}" != "None" ] && [ "${OAI_ID}" != "null" ]; then
  ETAG=$(aws cloudfront get-cloud-front-origin-access-identity --id "${OAI_ID}" --query 'ETag' --output text --no-cli-pager 2>/dev/null || echo "")
  [ -n "${ETAG}" ] && aws cloudfront delete-cloud-front-origin-access-identity --id "${OAI_ID}" --if-match "${ETAG}" --no-cli-pager 2>/dev/null || true
  echo "   ✓ Deleted: ${OAI_ID}"
else
  echo "   ✓ Not found"
fi

# ============================================================
# PHASE 3: Wait and finalize
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 3: Waiting for slow deletions..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Wait for CloudFront to be disabled, then delete
if [ -n "${CF_DIST_ID}" ]; then
  echo ""
  echo "   Waiting for CloudFront to be disabled..."
  for i in {1..60}; do
    STATUS=$(aws cloudfront get-distribution --id "${CF_DIST_ID}" --query 'Distribution.Status' --output text --no-cli-pager 2>/dev/null || echo "gone")
    [ "${STATUS}" = "Deployed" ] || [ "${STATUS}" = "gone" ] && break
    [ $((i % 6)) -eq 0 ] && echo "   ⏳ Status: ${STATUS}"
    sleep 10
  done
  if [ "${STATUS}" != "gone" ]; then
    ETAG=$(aws cloudfront get-distribution-config --id "${CF_DIST_ID}" --query 'ETag' --output text --no-cli-pager 2>/dev/null || echo "")
    [ -n "${ETAG}" ] && aws cloudfront delete-distribution --id "${CF_DIST_ID}" --if-match "${ETAG}" --no-cli-pager 2>/dev/null || true
    echo "   ✓ CloudFront deleted"
  fi
fi

# Verify slow deletions
echo ""
echo "   Verifying deletions..."
ALL_GONE=true

if [ -n "${MEMORY_ID}" ]; then
  echo -n "   Memory: "
  for i in {1..30}; do
    STATUS=$(aws bedrock-agentcore-control list-memories --region "${REGION}" --no-cli-pager \
      --query "memories[?id=='${MEMORY_ID}'].status | [0]" --output text 2>/dev/null || echo "")
    [ -z "${STATUS}" ] || [ "${STATUS}" = "None" ] && break
    sleep 5
  done
  [ -z "${STATUS}" ] || [ "${STATUS}" = "None" ] && echo "✓ Gone" || { echo "⚠️  Still exists"; ALL_GONE=false; }
fi

if [ -n "${RUNTIME_ID}" ]; then
  echo -n "   AI Agent Runtime: "
  for i in {1..30}; do
    STATUS=$(aws bedrock-agentcore-control list-agent-runtimes --region "${REGION}" --no-cli-pager \
      --query "agentRuntimes[?agentRuntimeId=='${RUNTIME_ID}'].status | [0]" --output text 2>/dev/null || echo "")
    [ -z "${STATUS}" ] || [ "${STATUS}" = "None" ] && break
    sleep 5
  done
  [ -z "${STATUS}" ] || [ "${STATUS}" = "None" ] && echo "✓ Gone" || { echo "⚠️  Still exists"; ALL_GONE=false; }
fi

if [ -n "${KB_ID}" ]; then
  echo -n "   Knowledge Base: "
  for i in {1..30}; do
    STATUS=$(aws bedrock-agent list-knowledge-bases --no-cli-pager \
      --query "knowledgeBaseSummaries[?knowledgeBaseId=='${KB_ID}'].status | [0]" --output text 2>/dev/null || echo "")
    [ -z "${STATUS}" ] || [ "${STATUS}" = "None" ] && break
    sleep 5
  done
  [ -z "${STATUS}" ] || [ "${STATUS}" = "None" ] && echo "✓ Gone" || { echo "⚠️  Still exists"; ALL_GONE=false; }
fi

# ============================================================
# PHASE 4: Delete VPC (if created by script)
# ============================================================
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Phase 4: Deleting VPC (if created by script)..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

VPC_NAME="workshop-vpc"
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" "Name=tag:created-by,Values=workshop-script" \
  --query 'Vpcs[0].VpcId' --output text --no-cli-pager 2>/dev/null || echo "")

if [ -n "${VPC_ID}" ] && [ "${VPC_ID}" != "None" ] && [ "${VPC_ID}" != "null" ]; then
  echo ""
  echo "[12] Deleting VPC: ${VPC_ID}..."

  # Delete NAT Gateway first (slow)
  NAT_GW_ID=$(aws ec2 describe-nat-gateways \
    --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=available,pending" \
    --query 'NatGateways[0].NatGatewayId' --output text --no-cli-pager 2>/dev/null || echo "")
  if [ -n "${NAT_GW_ID}" ] && [ "${NAT_GW_ID}" != "None" ]; then
    aws ec2 delete-nat-gateway --nat-gateway-id "${NAT_GW_ID}" --no-cli-pager 2>/dev/null || true
    echo "   ✓ NAT Gateway delete initiated: ${NAT_GW_ID}"
    echo "   ⏳ Waiting for NAT Gateway deletion..."
    for i in {1..60}; do
      STATUS=$(aws ec2 describe-nat-gateways --nat-gateway-ids "${NAT_GW_ID}" \
        --query 'NatGateways[0].State' --output text --no-cli-pager 2>/dev/null || echo "deleted")
      [ "${STATUS}" = "deleted" ] && break
      sleep 5
    done
  fi

  # Release Elastic IPs associated with VPC
  EIP_ALLOCS=$(aws ec2 describe-addresses \
    --filters "Name=tag:Name,Values=${VPC_NAME}-nat-eip" \
    --query 'Addresses[].AllocationId' --output text --no-cli-pager 2>/dev/null || echo "")
  for EIP_ALLOC in ${EIP_ALLOCS}; do
    [ -n "${EIP_ALLOC}" ] && [ "${EIP_ALLOC}" != "None" ] && \
      aws ec2 release-address --allocation-id "${EIP_ALLOC}" --no-cli-pager 2>/dev/null || true
  done
  [ -n "${EIP_ALLOCS}" ] && [ "${EIP_ALLOCS}" != "None" ] && echo "   ✓ Released Elastic IPs"

  # Wait for AgentCore ENIs to be deleted, then force delete if orphaned
  echo "   ⏳ Waiting for AgentCore ENIs to be released..."
  for i in {1..12}; do
    ENI_COUNT=$(aws ec2 describe-network-interfaces \
      --filters "Name=vpc-id,Values=${VPC_ID}" "Name=interface-type,Values=agentic_ai" \
      --query 'length(NetworkInterfaces)' --output text --no-cli-pager 2>/dev/null || echo "0")
    [ "${ENI_COUNT}" = "0" ] && break
    sleep 5
  done

  # Force delete orphaned AgentCore ENIs if still present
  if [ "${ENI_COUNT}" != "0" ]; then
    echo "   ⚠️  ${ENI_COUNT} orphaned AgentCore ENIs found, force deleting..."
    ENI_IDS=$(aws ec2 describe-network-interfaces \
      --filters "Name=vpc-id,Values=${VPC_ID}" "Name=interface-type,Values=agentic_ai" \
      --query 'NetworkInterfaces[].NetworkInterfaceId' --output text --no-cli-pager 2>/dev/null || echo "")
    for ENI_ID in ${ENI_IDS}; do
      [ -z "${ENI_ID}" ] || [ "${ENI_ID}" = "None" ] && continue
      # Get attachment ID
      ATTACH_ID=$(aws ec2 describe-network-interfaces --network-interface-ids "${ENI_ID}" \
        --query 'NetworkInterfaces[0].Attachment.AttachmentId' --output text --no-cli-pager 2>/dev/null || echo "")
      # Detach if attached
      if [ -n "${ATTACH_ID}" ] && [ "${ATTACH_ID}" != "None" ]; then
        aws ec2 detach-network-interface --attachment-id "${ATTACH_ID}" --force --no-cli-pager 2>/dev/null || true
        sleep 2
      fi
      # Delete ENI
      aws ec2 delete-network-interface --network-interface-id "${ENI_ID}" --no-cli-pager 2>/dev/null || true
    done
    echo "   ✓ Deleted orphaned ENIs"
  fi

  # Delete route tables (except main) - must delete routes and disassociate first
  RT_IDS=$(aws ec2 describe-route-tables \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text --no-cli-pager 2>/dev/null || echo "")
  for RT_ID in ${RT_IDS}; do
    [ -z "${RT_ID}" ] || [ "${RT_ID}" = "None" ] && continue
    # Delete non-local routes first
    ROUTE_CIDRS=$(aws ec2 describe-route-tables --route-table-ids "${RT_ID}" \
      --query 'RouteTables[0].Routes[?GatewayId!=`local`].DestinationCidrBlock' --output text --no-cli-pager 2>/dev/null || echo "")
    for CIDR in ${ROUTE_CIDRS}; do
      [ -n "${CIDR}" ] && [ "${CIDR}" != "None" ] && \
        aws ec2 delete-route --route-table-id "${RT_ID}" --destination-cidr-block "${CIDR}" --no-cli-pager 2>/dev/null || true
    done
    # Disassociate subnets
    ASSOC_IDS=$(aws ec2 describe-route-tables --route-table-ids "${RT_ID}" \
      --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text --no-cli-pager 2>/dev/null || echo "")
    for ASSOC_ID in ${ASSOC_IDS}; do
      [ -n "${ASSOC_ID}" ] && [ "${ASSOC_ID}" != "None" ] && \
        aws ec2 disassociate-route-table --association-id "${ASSOC_ID}" --no-cli-pager 2>/dev/null || true
    done
    aws ec2 delete-route-table --route-table-id "${RT_ID}" --no-cli-pager 2>/dev/null || true
  done
  [ -n "${RT_IDS}" ] && [ "${RT_IDS}" != "None" ] && echo "   ✓ Deleted route tables"

  # Delete subnets (after route table associations are removed and ENIs are gone)
  SUBNET_IDS=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'Subnets[].SubnetId' --output text --no-cli-pager 2>/dev/null || echo "")
  for SUBNET_ID in ${SUBNET_IDS}; do
    [ -n "${SUBNET_ID}" ] && [ "${SUBNET_ID}" != "None" ] && \
      aws ec2 delete-subnet --subnet-id "${SUBNET_ID}" --no-cli-pager 2>/dev/null || true
  done
  [ -n "${SUBNET_IDS}" ] && [ "${SUBNET_IDS}" != "None" ] && echo "   ✓ Deleted subnets"

  # Delete security groups (except default)
  SG_IDS=$(aws ec2 describe-security-groups \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
    --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text --no-cli-pager 2>/dev/null || echo "")
  for SG_ID in ${SG_IDS}; do
    aws ec2 delete-security-group --group-id "${SG_ID}" --no-cli-pager 2>/dev/null || true
  done
  [ -n "${SG_IDS}" ] && [ "${SG_IDS}" != "None" ] && echo "   ✓ Deleted security groups"

  # Detach and delete Internet Gateway
  IGW_ID=$(aws ec2 describe-internet-gateways \
    --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
    --query 'InternetGateways[0].InternetGatewayId' --output text --no-cli-pager 2>/dev/null || echo "")
  if [ -n "${IGW_ID}" ] && [ "${IGW_ID}" != "None" ]; then
    aws ec2 detach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" --no-cli-pager 2>/dev/null || true
    aws ec2 delete-internet-gateway --internet-gateway-id "${IGW_ID}" --no-cli-pager 2>/dev/null || true
    echo "   ✓ Deleted Internet Gateway"
  fi

  # Delete VPC
  aws ec2 delete-vpc --vpc-id "${VPC_ID}" --no-cli-pager 2>/dev/null && \
    echo "   ✓ Deleted VPC: ${VPC_ID}" || echo "   ⚠️  Failed to delete VPC (ENIs may still be releasing)"
else
  echo ""
  echo "[12] VPC not found or not created by script"
fi

echo ""
if [ "${ALL_GONE}" = true ]; then
  echo "✅ Cleanup Complete - All resources removed"
else
  echo "⚠️  Cleanup Complete - Some resources still deleting"
fi
