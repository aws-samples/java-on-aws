#!/bin/bash

# Workshop sync script
# Copies workshop-specific CloudFormation templates and IAM policies to workshop directories
# Target directories are sibling folders to the repo: ../../java-on-aws/static, etc.
# Structure: workshops/java-on-aws/static, workshops/java-on-eks/static, workshops/java-on-aws (this repo)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Change to infra directory (script may be called from different locations)
cd "$SCRIPT_DIR/../.." || {
    log_error "Failed to change to infra directory"
    exit 1
}

WORKSHOPS=("ide" "java-on-aws-immersion-day" "java-on-amazon-eks" "java-ai-agents" "java-spring-ai-agents")

log_info "Syncing CloudFormation templates and policies to workshop directories..."

synced_count=0

for workshop in "${WORKSHOPS[@]}"; do
    # Target is sibling to repo root: ../../{workshop}/static
    target_dir="../../$workshop/static"

    if [[ -d "$target_dir" ]]; then
        # Copy workshop-specific CloudFormation template -> workshop-stack.yaml
        template_file="cfn/${workshop}-stack.yaml"
        if [[ -f "$template_file" ]]; then
            cp "$template_file" "$target_dir/workshop-stack.yaml" || {
                log_error "Failed to copy template for $workshop"
                exit 1
            }
            log_success "Synced $template_file to $workshop/static/workshop-stack.yaml"
        else
            log_error "Template file $template_file not found"
            exit 1
        fi

        # Copy workshop-specific IAM policy -> iam-policy.json
        policy_file="cdk/src/main/resources/iam-policy-${workshop}.json"
        if [[ -f "$policy_file" ]]; then
            cp "$policy_file" "$target_dir/iam-policy.json" || {
                log_error "Failed to copy policy for $workshop"
                exit 1
            }
            log_success "Synced $policy_file to $workshop/static/iam-policy.json"
        else
            log_error "Policy file $policy_file not found"
            exit 1
        fi

        ((synced_count++))
    else
        log_info "Directory $target_dir not found, skipping $workshop"
    fi
done

if [[ $synced_count -eq 0 ]]; then
    log_warning "No workshop directories found. Expected sibling directories: ../../java-on-aws/static, etc."
else
    log_success "Synced $synced_count workshop(s) successfully!"
fi