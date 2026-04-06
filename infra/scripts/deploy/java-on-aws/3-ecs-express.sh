#!/bin/bash

# Deploy to Amazon ECS using Express Mode
# Based on: java-on-amazon-eks/content/deploy-containers/deploy-to-ecs/index.en.md (Express Mode tab)
# Usage: ./ecs-express.sh [app_name]

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

# App name from argument or default
APP_NAME="${1:-unicorn-store-spring}"

log_info "Deploying ${APP_NAME} to Amazon ECS (Express Mode)..."
log_info "AWS Account: $ACCOUNT_ID"
log_info "AWS Region: $AWS_REGION"

# Create the ECS cluster
log_info "Creating ECS cluster..."
aws ecs create-cluster --cluster-name ${APP_NAME} --no-cli-pager
log_success "ECS cluster created"

# Get VPC, subnets, and database security group
log_info "Getting VPC and networking info..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=workshop-vpc" \
  --query 'Vpcs[0].VpcId' --output text --no-cli-pager)
PUBLIC_SUBNET_IDS=$(aws ec2 describe-subnets \
  --filters "Name=tag:Name,Values=*Public*" "Name=vpc-id,Values=${VPC_ID}" \
  --query 'Subnets[*].SubnetId' --output json --no-cli-pager)
DB_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=workshop-db-sg" \
  --query 'SecurityGroups[0].GroupId' --output text --no-cli-pager)
echo "VPC: ${VPC_ID}, DB SG: ${DB_SG_ID}"
echo "Subnets: ${PUBLIC_SUBNET_IDS}"

# Get database secrets
log_info "Getting database secrets..."
DB_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id workshop-db-secret \
  --query 'ARN' --output text --no-cli-pager)
DB_CONNECTION_ARN=$(aws ssm get-parameter --name workshop-db-connection-string \
  --query 'Parameter.ARN' --output text --no-cli-pager)
echo "DB Secret: ${DB_SECRET_ARN}"
echo "DB Connection: ${DB_CONNECTION_ARN}"

# Deploy the ECS Express Mode service
log_info "Deploying ECS Express Mode service..."
aws ecs create-express-gateway-service \
  --service-name ${APP_NAME} \
  --cluster ${APP_NAME} \
  --cpu 1024 --memory 2048 \
  --execution-role-arn arn:aws:iam::${ACCOUNT_ID}:role/service-role/unicornstore-ecs-task-execution-role \
  --infrastructure-role-arn arn:aws:iam::${ACCOUNT_ID}:role/service-role/unicornstore-ecs-infrastructure-role \
  --task-role-arn arn:aws:iam::${ACCOUNT_ID}:role/service-role/unicornstore-ecs-task-role \
  --network-configuration "{\"subnets\": ${PUBLIC_SUBNET_IDS}, \"securityGroups\": [\"${DB_SG_ID}\"]}" \
  --primary-container "{
    \"image\": \"${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}:latest\",
    \"containerPort\": 8080,
    \"awsLogsConfiguration\": {
      \"logGroup\": \"/aws/ecs/${APP_NAME}\",
      \"logStreamPrefix\": \"ecs\"
    },
    \"secrets\": [
      {\"name\": \"SPRING_DATASOURCE_URL\", \"valueFrom\": \"${DB_CONNECTION_ARN}\"},
      {\"name\": \"SPRING_DATASOURCE_USERNAME\", \"valueFrom\": \"${DB_SECRET_ARN}:username::\"},
      {\"name\": \"SPRING_DATASOURCE_PASSWORD\", \"valueFrom\": \"${DB_SECRET_ARN}:password::\"}
    ]
  }" \
  --health-check-path /actuator/health \
  --no-cli-pager
log_success "ECS Express Mode service created"

# Speed up deployment configuration
log_info "Configuring faster deployments..."
aws ecs update-service \
  --cluster ${APP_NAME} \
  --service ${APP_NAME} \
  --deployment-configuration '{
    "maximumPercent": 200,
    "minimumHealthyPercent": 0,
    "bakeTimeInMinutes": 0,
    "canaryConfiguration": {"canaryPercent": 100, "canaryBakeTimeInMinutes": 0}
  }' \
  --no-cli-pager
log_success "Deployment configuration updated"

# Wait for service to become active
log_info "Waiting for service to become ACTIVE (this may take up to 10 minutes)..."
while [[ $(aws ecs describe-express-gateway-service \
  --service-arn arn:aws:ecs:${AWS_REGION}:${ACCOUNT_ID}:service/${APP_NAME}/${APP_NAME} \
  --no-cli-pager | jq -r '.service.status.statusCode') != "ACTIVE" ]]; do
  echo "Waiting for service to become ACTIVE ..." && sleep 15
done
echo "Service active."
sleep 30
SVC_URL=https://$(aws ecs describe-express-gateway-service \
  --service-arn arn:aws:ecs:${AWS_REGION}:${ACCOUNT_ID}:service/${APP_NAME}/${APP_NAME} \
  --no-cli-pager \
  | jq -r '.service.activeConfigurations[0].ingressPaths[0].endpoint')
while [[ $(curl -s -o /dev/null -w "%{http_code}" ${SVC_URL}/) != "200" ]]; do
  echo "Service not yet available ..." && sleep 15
done
echo "Service available."
echo ${SVC_URL} > ~/environment/.workshop-svc-url-ecs

log_success "ECS Express Mode deployment completed"
echo "✅ Success: Deployed to ECS Express Mode (URL: ${SVC_URL})"
