#!/bin/bash
# Idempotent cleanup script for workshop resources
# Deletes: ECR ai-jvm-analyzer repo, ECS cluster unicorn-store-spring (express or classic)

set -e

echo "=== Workshop Cleanup Script ==="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Get AWS account and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
AWS_REGION=${AWS_REGION:-$(aws configure get region 2>/dev/null || echo "us-east-1")}

if [ -z "$ACCOUNT_ID" ]; then
    log_error "Failed to get AWS account ID. Check AWS credentials."
    exit 1
fi

log_info "Account: ${ACCOUNT_ID}, Region: ${AWS_REGION}"
echo ""

# ============================================
# 1. Delete ECR repositories
# ============================================
echo "--- ECR Cleanup ---"

for REPO_NAME in ai-jvm-analyzer unicorn-spring-ai-agent unicorn-store-spring; do
    if aws ecr describe-repositories --repository-names ${REPO_NAME} --no-cli-pager >/dev/null 2>&1; then
        log_info "Deleting ECR repository: ${REPO_NAME}"
        aws ecr delete-repository --repository-name ${REPO_NAME} --force --no-cli-pager >/dev/null 2>&1
        log_info "ECR repository ${REPO_NAME} deleted"
    else
        log_warn "ECR repository ${REPO_NAME} does not exist, skipping"
    fi
done

echo ""

# ============================================
# 2. Delete ECS cluster: unicorn-store-spring (manual workshop deployment)
# ============================================
echo "--- ECS Cleanup ---"

CLUSTER_NAME="unicorn-store-spring"
SERVICE_NAME="unicorn-store-spring"

# Check if cluster exists
if ! aws ecs describe-clusters --clusters ${CLUSTER_NAME} --query 'clusters[?status==`ACTIVE`].clusterName' --output text --no-cli-pager 2>/dev/null | grep -q ${CLUSTER_NAME}; then
    log_warn "ECS cluster ${CLUSTER_NAME} does not exist or is not active, skipping"
else
    log_info "Found ECS cluster: ${CLUSTER_NAME}"

    # Check if this is an Express Gateway service
    EXPRESS_SERVICE_ARN="arn:aws:ecs:${AWS_REGION}:${ACCOUNT_ID}:service/${CLUSTER_NAME}/${SERVICE_NAME}"

    if aws ecs describe-express-gateway-service --service-arn ${EXPRESS_SERVICE_ARN} --no-cli-pager >/dev/null 2>&1; then
        log_info "Detected Express Gateway service, deleting..."

        # Delete Express Gateway service
        aws ecs delete-express-gateway-service --service-arn ${EXPRESS_SERVICE_ARN} --no-cli-pager >/dev/null 2>&1 || true

        # Wait for service deletion
        log_info "Waiting for Express Gateway service deletion..."
        sleep 30

    else
        # Classic ECS service
        if aws ecs describe-services --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} --query 'services[?status==`ACTIVE`].serviceName' --output text --no-cli-pager 2>/dev/null | grep -q ${SERVICE_NAME}; then
            log_info "Detected classic ECS service, deleting..."

            # Scale down service first
            aws ecs update-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --desired-count 0 --no-cli-pager >/dev/null 2>&1 || true
            sleep 10

            # Delete service
            aws ecs delete-service --cluster ${CLUSTER_NAME} --service ${SERVICE_NAME} --force --no-cli-pager >/dev/null 2>&1 || true

            # Wait for service deletion
            log_info "Waiting for service deletion..."
            aws ecs wait services-inactive --cluster ${CLUSTER_NAME} --services ${SERVICE_NAME} 2>/dev/null || sleep 30
        else
            log_warn "ECS service ${SERVICE_NAME} not found in cluster"
        fi
    fi

    # Delete task definitions
    log_info "Deleting task definitions..."
    TASK_DEFS=$(aws ecs list-task-definitions --family-prefix ${SERVICE_NAME} --query 'taskDefinitionArns[]' --output text --no-cli-pager 2>/dev/null || echo "")
    for TD in ${TASK_DEFS}; do
        aws ecs deregister-task-definition --task-definition ${TD} --no-cli-pager >/dev/null 2>&1 || true
        aws ecs delete-task-definitions --task-definitions ${TD} --no-cli-pager >/dev/null 2>&1 || true
    done

    # Delete cluster
    log_info "Deleting ECS cluster: ${CLUSTER_NAME}"
    aws ecs delete-cluster --cluster ${CLUSTER_NAME} --no-cli-pager >/dev/null 2>&1 || true
    log_info "ECS cluster deleted"
fi

echo ""

# ============================================
# 3. Delete ALB and related resources (classic ECS)
# ============================================
echo "--- Load Balancer Cleanup ---"

ALB_ARN=$(aws elbv2 describe-load-balancers --names ${SERVICE_NAME} --query 'LoadBalancers[0].LoadBalancerArn' --output text --no-cli-pager 2>/dev/null || echo "None")

if [ "$ALB_ARN" != "None" ] && [ -n "$ALB_ARN" ]; then
    log_info "Deleting ALB: ${SERVICE_NAME}"

    # Delete listeners first
    LISTENERS=$(aws elbv2 describe-listeners --load-balancer-arn ${ALB_ARN} --query 'Listeners[].ListenerArn' --output text --no-cli-pager 2>/dev/null || echo "")
    for LISTENER in ${LISTENERS}; do
        aws elbv2 delete-listener --listener-arn ${LISTENER} --no-cli-pager >/dev/null 2>&1 || true
    done

    # Delete load balancer
    aws elbv2 delete-load-balancer --load-balancer-arn ${ALB_ARN} --no-cli-pager >/dev/null 2>&1 || true
    log_info "ALB deleted, waiting for cleanup..."
    sleep 30
else
    log_warn "ALB ${SERVICE_NAME} does not exist, skipping"
fi

# Delete target group
TG_ARN=$(aws elbv2 describe-target-groups --names ${SERVICE_NAME} --query 'TargetGroups[0].TargetGroupArn' --output text --no-cli-pager 2>/dev/null || echo "None")

if [ "$TG_ARN" != "None" ] && [ -n "$TG_ARN" ]; then
    log_info "Deleting target group: ${SERVICE_NAME}"
    aws elbv2 delete-target-group --target-group-arn ${TG_ARN} --no-cli-pager >/dev/null 2>&1 || true
    log_info "Target group deleted"
else
    log_warn "Target group ${SERVICE_NAME} does not exist, skipping"
fi

echo ""

# ============================================
# 4. Delete Security Groups (classic ECS)
# ============================================
echo "--- Security Group Cleanup ---"

# Get VPC ID
VPC_ID=$(aws ec2 describe-vpcs --filters "Name=tag:Name,Values=workshop-vpc" --query 'Vpcs[0].VpcId' --output text --no-cli-pager 2>/dev/null || echo "")

if [ -n "$VPC_ID" ] && [ "$VPC_ID" != "None" ]; then
    # Delete ALB security group
    ALB_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=unicorn-store-spring-alb-sg" "Name=vpc-id,Values=${VPC_ID}" --query 'SecurityGroups[0].GroupId' --output text --no-cli-pager 2>/dev/null || echo "None")

    if [ "$ALB_SG_ID" != "None" ] && [ -n "$ALB_SG_ID" ]; then
        log_info "Deleting security group: unicorn-store-spring-alb-sg"
        aws ec2 delete-security-group --group-id ${ALB_SG_ID} --no-cli-pager >/dev/null 2>&1 || log_warn "Could not delete ALB SG (may have dependencies)"
    else
        log_warn "Security group unicorn-store-spring-alb-sg does not exist, skipping"
    fi

    # Delete ECS security group
    ECS_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=unicorn-store-spring-ecs-sg" "Name=vpc-id,Values=${VPC_ID}" --query 'SecurityGroups[0].GroupId' --output text --no-cli-pager 2>/dev/null || echo "None")

    if [ "$ECS_SG_ID" != "None" ] && [ -n "$ECS_SG_ID" ]; then
        log_info "Deleting security group: unicorn-store-spring-ecs-sg"
        aws ec2 delete-security-group --group-id ${ECS_SG_ID} --no-cli-pager >/dev/null 2>&1 || log_warn "Could not delete ECS SG (may have dependencies)"
    else
        log_warn "Security group unicorn-store-spring-ecs-sg does not exist, skipping"
    fi
fi

echo ""

# ============================================
# 5. Delete CloudWatch Log Groups
# ============================================
echo "--- CloudWatch Logs Cleanup ---"

LOG_GROUP="/aws/ecs/unicorn-store-spring"
if aws logs describe-log-groups --log-group-name-prefix ${LOG_GROUP} --query 'logGroups[0].logGroupName' --output text --no-cli-pager 2>/dev/null | grep -q ${LOG_GROUP}; then
    log_info "Deleting log group: ${LOG_GROUP}"
    aws logs delete-log-group --log-group-name ${LOG_GROUP} --no-cli-pager >/dev/null 2>&1 || true
    log_info "Log group deleted"
else
    log_warn "Log group ${LOG_GROUP} does not exist, skipping"
fi

echo ""

# ============================================
# 6. Delete EKS Pod Identity Association (ai-jvm-analyzer)
# ============================================
echo "--- EKS Pod Identity Cleanup ---"

CLUSTER_NAME_EKS="workshop-eks"

# Check if EKS cluster exists
if aws eks describe-cluster --name ${CLUSTER_NAME_EKS} --no-cli-pager >/dev/null 2>&1; then
    # Delete ai-jvm-analyzer pod identity association
    ASSOC_ID=$(aws eks list-pod-identity-associations --cluster-name ${CLUSTER_NAME_EKS} --query "associations[?serviceAccount=='ai-jvm-analyzer' && namespace=='monitoring'].associationId" --output text --no-cli-pager 2>/dev/null || echo "")

    if [ -n "$ASSOC_ID" ] && [ "$ASSOC_ID" != "None" ]; then
        log_info "Deleting Pod Identity association for ai-jvm-analyzer"
        aws eks delete-pod-identity-association --cluster-name ${CLUSTER_NAME_EKS} --association-id ${ASSOC_ID} --no-cli-pager >/dev/null 2>&1 || true
        log_info "Pod Identity association deleted"
    else
        log_warn "Pod Identity association for ai-jvm-analyzer does not exist, skipping"
    fi
else
    log_warn "EKS cluster ${CLUSTER_NAME_EKS} does not exist, skipping Pod Identity cleanup"
fi

echo ""
echo "=== Cleanup Complete ==="
