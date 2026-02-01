#!/bin/bash
# ============================================================
# 09-vpc.sh - Create Workshop VPC for AgentCore
# ============================================================
# Creates VPC with public/private subnets in supported AZs
# AgentCore VPC mode requires: use1-az1, use1-az2, use1-az4
# Idempotent - safe to run multiple times
# ============================================================
set -e

REGION=${AWS_REGION:-us-east-1}
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --no-cli-pager)
VPC_NAME="workshop-vpc"
VPC_CIDR="10.0.0.0/16"
SG_NAME="workshop-sg"

echo "🌐 Creating Workshop VPC"
echo ""
echo "Region: ${REGION}"
echo "VPC Name: ${VPC_NAME}"
echo ""

# ============================================================
# 1. Check/Create VPC
# ============================================================
echo "1️⃣  Checking VPC..."
VPC_ID=$(aws ec2 describe-vpcs \
  --filters "Name=tag:Name,Values=${VPC_NAME}" \
  --query 'Vpcs[0].VpcId' --output text --no-cli-pager 2>/dev/null || echo "")

if [ -n "${VPC_ID}" ] && [ "${VPC_ID}" != "None" ] && [ "${VPC_ID}" != "null" ]; then
  echo "   ✓ VPC exists: ${VPC_ID}"
else
  VPC_ID=$(aws ec2 create-vpc \
    --cidr-block "${VPC_CIDR}" \
    --tag-specifications "ResourceType=vpc,Tags=[{Key=Name,Value=${VPC_NAME}},{Key=created-by,Value=workshop-script}]" \
    --query 'Vpc.VpcId' --output text --no-cli-pager)

  aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-hostnames --no-cli-pager
  aws ec2 modify-vpc-attribute --vpc-id "${VPC_ID}" --enable-dns-support --no-cli-pager
  echo "   ✓ Created VPC: ${VPC_ID}"
fi

# ============================================================
# 2. Create Internet Gateway
# ============================================================
echo ""
echo "2️⃣  Checking Internet Gateway..."
IGW_ID=$(aws ec2 describe-internet-gateways \
  --filters "Name=attachment.vpc-id,Values=${VPC_ID}" \
  --query 'InternetGateways[0].InternetGatewayId' --output text --no-cli-pager 2>/dev/null || echo "")

if [ -n "${IGW_ID}" ] && [ "${IGW_ID}" != "None" ] && [ "${IGW_ID}" != "null" ]; then
  echo "   ✓ Internet Gateway exists: ${IGW_ID}"
else
  IGW_ID=$(aws ec2 create-internet-gateway \
    --tag-specifications "ResourceType=internet-gateway,Tags=[{Key=Name,Value=${VPC_NAME}-igw}]" \
    --query 'InternetGateway.InternetGatewayId' --output text --no-cli-pager)

  aws ec2 attach-internet-gateway --internet-gateway-id "${IGW_ID}" --vpc-id "${VPC_ID}" --no-cli-pager
  echo "   ✓ Created Internet Gateway: ${IGW_ID}"
fi

# ============================================================
# 3. Create Public Subnets (in supported AZs)
# ============================================================
echo ""
echo "3️⃣  Creating public subnets..."

# AgentCore supported AZ IDs for us-east-1: use1-az1, use1-az2, use1-az4
# Using simple variables instead of associative arrays for compatibility
PUBLIC_SUBNET_IDS=""

# Helper function to get public CIDR for AZ
get_public_cidr() {
  case "$1" in
    use1-az1) echo "10.0.1.0/24" ;;
    use1-az2) echo "10.0.2.0/24" ;;
    use1-az4) echo "10.0.3.0/24" ;;
  esac
}

for AZ_ID in use1-az1 use1-az2 use1-az4; do
  CIDR=$(get_public_cidr "${AZ_ID}")

  # Get AZ name from AZ ID
  AZ_NAME=$(aws ec2 describe-availability-zones \
    --filters "Name=zone-id,Values=${AZ_ID}" \
    --query 'AvailabilityZones[0].ZoneName' --output text --no-cli-pager 2>/dev/null || echo "")

  if [ -z "${AZ_NAME}" ] || [ "${AZ_NAME}" = "None" ]; then
    echo "   ⚠️  AZ ${AZ_ID} not available in ${REGION}, skipping"
    continue
  fi

  SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
              "Name=cidr-block,Values=${CIDR}" \
    --query 'Subnets[0].SubnetId' --output text --no-cli-pager 2>/dev/null || echo "")

  if [ -n "${SUBNET_ID}" ] && [ "${SUBNET_ID}" != "None" ] && [ "${SUBNET_ID}" != "null" ]; then
    echo "   ✓ Public subnet exists in ${AZ_ID}: ${SUBNET_ID}"
  else
    SUBNET_ID=$(aws ec2 create-subnet \
      --vpc-id "${VPC_ID}" \
      --cidr-block "${CIDR}" \
      --availability-zone "${AZ_NAME}" \
      --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-public-${AZ_ID}},{Key=aws-cdk:subnet-type,Value=Public}]" \
      --query 'Subnet.SubnetId' --output text --no-cli-pager)

    aws ec2 modify-subnet-attribute --subnet-id "${SUBNET_ID}" --map-public-ip-on-launch --no-cli-pager
    echo "   ✓ Created public subnet in ${AZ_ID}: ${SUBNET_ID}"
  fi
  PUBLIC_SUBNET_IDS="${PUBLIC_SUBNET_IDS} ${SUBNET_ID}"
done

# Convert to array
PUBLIC_SUBNET_IDS=(${PUBLIC_SUBNET_IDS})

# ============================================================
# 4. Create Private Subnets (in supported AZs)
# ============================================================
echo ""
echo "4️⃣  Creating private subnets..."

PRIVATE_SUBNET_IDS=""

# Helper function to get private CIDR for AZ
get_private_cidr() {
  case "$1" in
    use1-az1) echo "10.0.11.0/24" ;;
    use1-az2) echo "10.0.12.0/24" ;;
    use1-az4) echo "10.0.13.0/24" ;;
  esac
}

for AZ_ID in use1-az1 use1-az2 use1-az4; do
  CIDR=$(get_private_cidr "${AZ_ID}")

  AZ_NAME=$(aws ec2 describe-availability-zones \
    --filters "Name=zone-id,Values=${AZ_ID}" \
    --query 'AvailabilityZones[0].ZoneName' --output text --no-cli-pager 2>/dev/null || echo "")

  if [ -z "${AZ_NAME}" ] || [ "${AZ_NAME}" = "None" ]; then
    continue
  fi

  SUBNET_ID=$(aws ec2 describe-subnets \
    --filters "Name=vpc-id,Values=${VPC_ID}" \
              "Name=cidr-block,Values=${CIDR}" \
    --query 'Subnets[0].SubnetId' --output text --no-cli-pager 2>/dev/null || echo "")

  if [ -n "${SUBNET_ID}" ] && [ "${SUBNET_ID}" != "None" ] && [ "${SUBNET_ID}" != "null" ]; then
    echo "   ✓ Private subnet exists in ${AZ_ID}: ${SUBNET_ID}"
  else
    SUBNET_ID=$(aws ec2 create-subnet \
      --vpc-id "${VPC_ID}" \
      --cidr-block "${CIDR}" \
      --availability-zone "${AZ_NAME}" \
      --tag-specifications "ResourceType=subnet,Tags=[{Key=Name,Value=${VPC_NAME}-private-${AZ_ID}},{Key=aws-cdk:subnet-type,Value=Private}]" \
      --query 'Subnet.SubnetId' --output text --no-cli-pager)
    echo "   ✓ Created private subnet in ${AZ_ID}: ${SUBNET_ID}"
  fi
  PRIVATE_SUBNET_IDS="${PRIVATE_SUBNET_IDS} ${SUBNET_ID}"
done

# Convert to array
PRIVATE_SUBNET_IDS=(${PRIVATE_SUBNET_IDS})

# ============================================================
# 5. Create NAT Gateway (in first public subnet)
# ============================================================
echo ""
echo "5️⃣  Checking NAT Gateway..."

NAT_GW_ID=$(aws ec2 describe-nat-gateways \
  --filter "Name=vpc-id,Values=${VPC_ID}" "Name=state,Values=available,pending" \
  --query 'NatGateways[0].NatGatewayId' --output text --no-cli-pager 2>/dev/null || echo "")

if [ -n "${NAT_GW_ID}" ] && [ "${NAT_GW_ID}" != "None" ] && [ "${NAT_GW_ID}" != "null" ]; then
  echo "   ✓ NAT Gateway exists: ${NAT_GW_ID}"
else
  # Allocate Elastic IP
  EIP_ALLOC=$(aws ec2 allocate-address \
    --domain vpc \
    --tag-specifications "ResourceType=elastic-ip,Tags=[{Key=Name,Value=${VPC_NAME}-nat-eip}]" \
    --query 'AllocationId' --output text --no-cli-pager)
  echo "   ✓ Allocated Elastic IP: ${EIP_ALLOC}"

  # Create NAT Gateway in first public subnet
  NAT_GW_ID=$(aws ec2 create-nat-gateway \
    --subnet-id "${PUBLIC_SUBNET_IDS[0]}" \
    --allocation-id "${EIP_ALLOC}" \
    --tag-specifications "ResourceType=natgateway,Tags=[{Key=Name,Value=${VPC_NAME}-nat}]" \
    --query 'NatGateway.NatGatewayId' --output text --no-cli-pager)
  echo "   ✓ Created NAT Gateway: ${NAT_GW_ID}"

  echo "   ⏳ Waiting for NAT Gateway to become available..."
  aws ec2 wait nat-gateway-available --nat-gateway-ids "${NAT_GW_ID}" --no-cli-pager
  echo "   ✓ NAT Gateway is available"
fi

# ============================================================
# 6. Create/Update Route Tables
# ============================================================
echo ""
echo "6️⃣  Configuring route tables..."

# Public route table
PUBLIC_RT_ID=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${VPC_NAME}-public-rt" \
  --query 'RouteTables[0].RouteTableId' --output text --no-cli-pager 2>/dev/null || echo "")

if [ -z "${PUBLIC_RT_ID}" ] || [ "${PUBLIC_RT_ID}" = "None" ] || [ "${PUBLIC_RT_ID}" = "null" ]; then
  PUBLIC_RT_ID=$(aws ec2 create-route-table \
    --vpc-id "${VPC_ID}" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-public-rt}]" \
    --query 'RouteTable.RouteTableId' --output text --no-cli-pager)
  echo "   ✓ Created public route table: ${PUBLIC_RT_ID}"
fi

# Add route to Internet Gateway
aws ec2 create-route \
  --route-table-id "${PUBLIC_RT_ID}" \
  --destination-cidr-block "0.0.0.0/0" \
  --gateway-id "${IGW_ID}" \
  --no-cli-pager 2>/dev/null || true

# Associate public subnets
for SUBNET_ID in "${PUBLIC_SUBNET_IDS[@]}"; do
  aws ec2 associate-route-table \
    --route-table-id "${PUBLIC_RT_ID}" \
    --subnet-id "${SUBNET_ID}" \
    --no-cli-pager 2>/dev/null || true
done
echo "   ✓ Public route table configured"

# Private route table
PRIVATE_RT_ID=$(aws ec2 describe-route-tables \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=${VPC_NAME}-private-rt" \
  --query 'RouteTables[0].RouteTableId' --output text --no-cli-pager 2>/dev/null || echo "")

if [ -z "${PRIVATE_RT_ID}" ] || [ "${PRIVATE_RT_ID}" = "None" ] || [ "${PRIVATE_RT_ID}" = "null" ]; then
  PRIVATE_RT_ID=$(aws ec2 create-route-table \
    --vpc-id "${VPC_ID}" \
    --tag-specifications "ResourceType=route-table,Tags=[{Key=Name,Value=${VPC_NAME}-private-rt}]" \
    --query 'RouteTable.RouteTableId' --output text --no-cli-pager)
  echo "   ✓ Created private route table: ${PRIVATE_RT_ID}"
fi

# Add route to NAT Gateway
aws ec2 create-route \
  --route-table-id "${PRIVATE_RT_ID}" \
  --destination-cidr-block "0.0.0.0/0" \
  --nat-gateway-id "${NAT_GW_ID}" \
  --no-cli-pager 2>/dev/null || true

# Associate private subnets
for SUBNET_ID in "${PRIVATE_SUBNET_IDS[@]}"; do
  aws ec2 associate-route-table \
    --route-table-id "${PRIVATE_RT_ID}" \
    --subnet-id "${SUBNET_ID}" \
    --no-cli-pager 2>/dev/null || true
done
echo "   ✓ Private route table configured"

# ============================================================
# 7. Create Security Group
# ============================================================
echo ""
echo "7️⃣  Checking security group..."

SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=group-name,Values=${SG_NAME}" \
  --query 'SecurityGroups[0].GroupId' --output text --no-cli-pager 2>/dev/null || echo "")

if [ -n "${SG_ID}" ] && [ "${SG_ID}" != "None" ] && [ "${SG_ID}" != "null" ]; then
  echo "   ✓ Security group exists: ${SG_ID}"
else
  SG_ID=$(aws ec2 create-security-group \
    --group-name "${SG_NAME}" \
    --description "Workshop security group for AgentCore" \
    --vpc-id "${VPC_ID}" \
    --tag-specifications "ResourceType=security-group,Tags=[{Key=Name,Value=${SG_NAME}}]" \
    --query 'GroupId' --output text --no-cli-pager)

  # Allow all outbound traffic
  aws ec2 authorize-security-group-egress \
    --group-id "${SG_ID}" \
    --protocol all \
    --cidr 0.0.0.0/0 \
    --no-cli-pager 2>/dev/null || true

  # Allow inbound from VPC CIDR
  aws ec2 authorize-security-group-ingress \
    --group-id "${SG_ID}" \
    --protocol all \
    --cidr "${VPC_CIDR}" \
    --no-cli-pager 2>/dev/null || true

  echo "   ✓ Created security group: ${SG_ID}"
fi

# ============================================================
# Summary
# ============================================================
PRIVATE_SUBNET_JSON=$(printf '%s\n' "${PRIVATE_SUBNET_IDS[@]}" | jq -R . | jq -s .)

echo ""
echo "✅ VPC Setup Complete"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🌐 VPC ID: ${VPC_ID}"
echo "🔒 Security Group: ${SG_ID}"
echo "📡 Private Subnets: ${PRIVATE_SUBNET_JSON}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
