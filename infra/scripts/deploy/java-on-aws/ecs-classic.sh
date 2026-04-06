#!/bin/bash

# Deploy to Amazon ECS (Classic/Manual setup)
# Based on: java-on-amazon-eks/content/deploy-containers/deploy-to-ecs/index.en.md (Amazon ECS tab)
# Usage: ./ecs-classic.sh [app_name]

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

# Source environment variables
source /etc/profile.d/workshop.sh

# App name from argument or default
APP_NAME="${1:-unicorn-store-spring}"
APP_DIR=~/environment/${APP_NAME}

log_info "Deploying ${APP_NAME} to Amazon ECS (Classic)..."
log_info "AWS Account: $ACCOUNT_ID"
log_info "AWS Region: $AWS_REGION"

# Get database secrets
log_info "Getting database secrets..."
DB_CONNECTION_ARN=$(aws ssm get-parameter --name "workshop-db-connection-string" \
  --query 'Parameter.ARN' --output text --no-cli-pager)
DB_SECRET_ARN=$(aws secretsmanager describe-secret --secret-id workshop-db-secret \
  --query 'ARN' --output text --no-cli-pager)

# Create ECS container definition
log_info "Creating ECS container definition..."
cat <<EOF > ${APP_DIR}/ecs-container-definitions.json
[
    {
        "name": "Main",
        "image": "${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${APP_NAME}:latest",
        "portMappings": [
            {
                "name": "${APP_NAME}-8080-tcp",
                "containerPort": 8080,
                "hostPort": 8080,
                "protocol": "tcp",
                "appProtocol": "http"
            }
        ],
        "essential": true,
        "secrets": [
            {
                "name": "SPRING_DATASOURCE_URL",
                "valueFrom": "${DB_CONNECTION_ARN}"
            },
            {
                "name": "SPRING_DATASOURCE_USERNAME",
                "valueFrom": "${DB_SECRET_ARN}:username::"
            },
            {
                "name": "SPRING_DATASOURCE_PASSWORD",
                "valueFrom": "${DB_SECRET_ARN}:password::"
            }
        ],
        "logConfiguration": {
            "logDriver": "awslogs",
            "options": {
                "awslogs-group": "/aws/ecs/${APP_NAME}",
                "awslogs-create-group": "true",
                "awslogs-region": "${AWS_REGION}",
                "awslogs-stream-prefix": "ecs"
            }
        }
    }
]
EOF
log_success "Container definition created"

# Register task definition
log_info "Registering task definition..."
aws ecs register-task-definition --family ${APP_NAME} --no-cli-pager \
  --requires-compatibilities FARGATE --network-mode awsvpc \
  --cpu 1024 --memory 2048 \
  --task-role-arn arn:aws:iam::${ACCOUNT_ID}:role/service-role/unicornstore-ecs-task-role \
  --execution-role-arn arn:aws:iam::${ACCOUNT_ID}:role/service-role/unicornstore-ecs-task-execution-role \
  --container-definitions file://${APP_DIR}/ecs-container-definitions.json \
  --runtime-platform '{"cpuArchitecture":"X86_64","operatingSystemFamily":"LINUX"}'
rm ${APP_DIR}/ecs-container-definitions.json
log_success "Task definition registered"

# Create ECS cluster
log_info "Creating ECS cluster..."
aws ecs create-cluster --cluster-name ${APP_NAME} --no-cli-pager
log_success "ECS cluster created"

# Get VPC and subnet IDs
log_info "Getting VPC and networking info..."
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=workshop-vpc" \
  --query 'Vpcs[0].VpcId' --output text --no-cli-pager)
SUBNET_PUBLIC_1=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*Public*" \
  --query 'Subnets[0].SubnetId' --output text --no-cli-pager)
SUBNET_PUBLIC_2=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*Public*" \
  --query 'Subnets[1].SubnetId' --output text --no-cli-pager)
SUBNET_PRIVATE_1=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*Private*" \
  --query 'Subnets[0].SubnetId' --output text --no-cli-pager)
SUBNET_PRIVATE_2=$(aws ec2 describe-subnets \
  --filters "Name=vpc-id,Values=${VPC_ID}" "Name=tag:Name,Values=*Private*" \
  --query 'Subnets[1].SubnetId' --output text --no-cli-pager)
echo "VPC: ${VPC_ID}"
echo "Public: ${SUBNET_PUBLIC_1}, ${SUBNET_PUBLIC_2}"
echo "Private: ${SUBNET_PRIVATE_1}, ${SUBNET_PRIVATE_2}"

# Create security group for ALB
log_info "Creating ALB security group..."
aws ec2 create-security-group \
  --group-name ${APP_NAME}-alb-sg \
  --description "Security group for ALB" \
  --vpc-id ${VPC_ID} \
  --no-cli-pager
ALB_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${APP_NAME}-alb-sg" \
  --query 'SecurityGroups[0].GroupId' --output text --no-cli-pager)
aws ec2 authorize-security-group-ingress \
  --group-id ${ALB_SG_ID} \
  --protocol tcp \
  --port 80 \
  --cidr 0.0.0.0/0 \
  --no-cli-pager
echo "ALB SG: ${ALB_SG_ID}"
log_success "ALB security group created"

# Create security group for ECS tasks
log_info "Creating ECS security group..."
DB_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=workshop-db-sg" \
  --query 'SecurityGroups[0].GroupId' --output text --no-cli-pager)
aws ec2 create-security-group \
  --group-name ${APP_NAME}-ecs-sg \
  --description "Security group for ECS tasks" \
  --vpc-id ${VPC_ID} \
  --no-cli-pager
ECS_SG_ID=$(aws ec2 describe-security-groups \
  --filters "Name=group-name,Values=${APP_NAME}-ecs-sg" \
  --query 'SecurityGroups[0].GroupId' --output text --no-cli-pager)
aws ec2 authorize-security-group-ingress \
  --group-id ${ECS_SG_ID} \
  --protocol tcp \
  --port 8080 \
  --source-group ${ALB_SG_ID} \
  --no-cli-pager
echo "ECS SG: ${ECS_SG_ID}, DB SG: ${DB_SG_ID}"
log_success "ECS security group created"

# Create Application Load Balancer
log_info "Creating Application Load Balancer..."
aws elbv2 create-load-balancer \
  --name ${APP_NAME} \
  --subnets ${SUBNET_PUBLIC_1} ${SUBNET_PUBLIC_2} \
  --security-groups ${ALB_SG_ID} \
  --no-cli-pager
log_success "ALB created"

# Create target group
log_info "Creating target group..."
aws elbv2 create-target-group \
  --name ${APP_NAME} \
  --port 8080 \
  --protocol HTTP \
  --vpc-id ${VPC_ID} \
  --target-type ip \
  --health-check-path /actuator/health \
  --no-cli-pager
log_success "Target group created"

# Create listener
log_info "Creating listener..."
ALB_ARN=$(aws elbv2 describe-load-balancers --names ${APP_NAME} \
  --query 'LoadBalancers[0].LoadBalancerArn' --output text --no-cli-pager)
TG_ARN=$(aws elbv2 describe-target-groups --names ${APP_NAME} \
  --query 'TargetGroups[0].TargetGroupArn' --output text --no-cli-pager)
aws elbv2 create-listener \
  --load-balancer-arn ${ALB_ARN} \
  --port 80 \
  --protocol HTTP \
  --default-actions Type=forward,TargetGroupArn=${TG_ARN} \
  --no-cli-pager
log_success "Listener created"

# Create ECS service
log_info "Creating ECS service..."
aws ecs create-service \
  --cluster ${APP_NAME} \
  --service-name ${APP_NAME} \
  --task-definition ${APP_NAME} \
  --desired-count 1 \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[${SUBNET_PRIVATE_1},${SUBNET_PRIVATE_2}],securityGroups=[${ECS_SG_ID},${DB_SG_ID}],assignPublicIp=DISABLED}" \
  --load-balancers "targetGroupArn=${TG_ARN},containerName=Main,containerPort=8080" \
  --no-cli-pager
log_success "ECS service created"

# Wait for service to stabilize
log_info "Waiting for service to stabilize..."
aws ecs wait services-stable \
  --cluster ${APP_NAME} \
  --services ${APP_NAME}
SVC_URL=http://$(aws elbv2 describe-load-balancers --names ${APP_NAME} \
  --query 'LoadBalancers[0].DNSName' --output text --no-cli-pager)
while [[ $(curl -s -o /dev/null -w "%{http_code}" ${SVC_URL}/) != "200" ]]; do
  echo "Service not yet available ..." && sleep 15
done
echo "Service available."
echo ${SVC_URL} > ~/environment/.workshop-svc-url-ecs

log_success "ECS Classic deployment completed"
echo "✅ Success: Deployed to ECS Classic (URL: ${SVC_URL})"
