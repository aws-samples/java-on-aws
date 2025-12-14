#!/bin/bash

# Resource readiness checking utilities
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Wait for CloudFormation stack to be in CREATE_COMPLETE or UPDATE_COMPLETE state
wait_for_stack() {
    local stack_name=$1
    local timeout=${2:-1800}  # 30 minutes default
    local start_time=$(date +%s)

    log_info "Waiting for CloudFormation stack '$stack_name' to be ready (timeout: ${timeout}s)..."

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -ge $timeout ]; then
            log_error "TIMEOUT: Stack '$stack_name' did not become ready within ${timeout} seconds"
            log_error "Check CloudFormation console for stack events and details"
            return 1
        fi

        local stack_status=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || echo "STACK_NOT_FOUND")

        case $stack_status in
            "CREATE_COMPLETE"|"UPDATE_COMPLETE")
                log_success "Stack '$stack_name' is ready"
                return 0
                ;;
            "CREATE_FAILED"|"UPDATE_FAILED"|"ROLLBACK_COMPLETE"|"DELETE_COMPLETE")
                log_error "Stack '$stack_name' is in failed state: $stack_status"
                log_error "Check CloudFormation console for error details"
                return 1
                ;;
            "STACK_NOT_FOUND")
                log_error "Stack '$stack_name' not found"
                return 1
                ;;
            *)
                log_info "Stack '$stack_name' status: $stack_status (elapsed: ${elapsed}s)"
                sleep 30
                ;;
        esac
    done
}

# Wait for EKS cluster to be active
wait_for_eks_cluster() {
    local cluster_name=$1
    local timeout=${2:-1200}  # 20 minutes default
    local start_time=$(date +%s)

    log_info "Waiting for EKS cluster '$cluster_name' to be active (timeout: ${timeout}s)..."

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -ge $timeout ]; then
            log_error "TIMEOUT: EKS cluster '$cluster_name' did not become active within ${timeout} seconds"
            log_error "Check EKS console for cluster status and events"
            return 1
        fi

        local cluster_status=$(aws eks describe-cluster --name "$cluster_name" --query 'cluster.status' --output text 2>/dev/null || echo "NOT_FOUND")

        case $cluster_status in
            "ACTIVE")
                log_success "EKS cluster '$cluster_name' is active"
                return 0
                ;;
            "FAILED"|"DELETING")
                log_error "EKS cluster '$cluster_name' is in failed state: $cluster_status"
                return 1
                ;;
            "NOT_FOUND")
                log_error "EKS cluster '$cluster_name' not found"
                return 1
                ;;
            *)
                log_info "EKS cluster '$cluster_name' status: $cluster_status (elapsed: ${elapsed}s)"
                sleep 30
                ;;
        esac
    done
}

# Wait for RDS instance to be available
wait_for_rds_instance() {
    local instance_id=$1
    local timeout=${2:-900}  # 15 minutes default
    local start_time=$(date +%s)

    log_info "Waiting for RDS instance '$instance_id' to be available (timeout: ${timeout}s)..."

    while true; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ $elapsed -ge $timeout ]; then
            log_error "TIMEOUT: RDS instance '$instance_id' did not become available within ${timeout} seconds"
            log_error "Check RDS console for instance status and events"
            return 1
        fi

        local instance_status=$(aws rds describe-db-instances --db-instance-identifier "$instance_id" --query 'DBInstances[0].DBInstanceStatus' --output text 2>/dev/null || echo "NOT_FOUND")

        case $instance_status in
            "available")
                log_success "RDS instance '$instance_id' is available"
                return 0
                ;;
            "failed"|"incompatible-parameters"|"incompatible-restore")
                log_error "RDS instance '$instance_id' is in failed state: $instance_status"
                return 1
                ;;
            "NOT_FOUND")
                log_error "RDS instance '$instance_id' not found"
                return 1
                ;;
            *)
                log_info "RDS instance '$instance_id' status: $instance_status (elapsed: ${elapsed}s)"
                sleep 30
                ;;
        esac
    done
}

# Main function to wait for resources based on stack name
wait_for_resources() {
    local stack_name=$1

    if [ -z "$stack_name" ]; then
        log_error "Stack name is required"
        return 1
    fi

    log_info "Starting resource readiness check for stack: $stack_name"

    # Always wait for the CloudFormation stack first
    wait_for_stack "$stack_name"

    # Get stack outputs to determine what resources to wait for
    local stack_outputs=$(aws cloudformation describe-stacks --stack-name "$stack_name" --query 'Stacks[0].Outputs' --output json 2>/dev/null || echo "[]")

    # Check for EKS cluster
    local cluster_name=$(echo "$stack_outputs" | jq -r '.[] | select(.OutputKey=="EksClusterName") | .OutputValue' 2>/dev/null || echo "")
    if [ -n "$cluster_name" ] && [ "$cluster_name" != "null" ]; then
        wait_for_eks_cluster "$cluster_name"
    fi

    # Check for RDS instance
    local rds_instance=$(echo "$stack_outputs" | jq -r '.[] | select(.OutputKey=="DatabaseInstanceId") | .OutputValue' 2>/dev/null || echo "")
    if [ -n "$rds_instance" ] && [ "$rds_instance" != "null" ]; then
        wait_for_rds_instance "$rds_instance"
    fi

    log_success "All resources for stack '$stack_name' are ready"
}

# If script is executed directly (not sourced), run the main function
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    if [ $# -eq 0 ]; then
        log_error "Usage: $0 <stack-name>"
        exit 1
    fi
    wait_for_resources "$1"
fi