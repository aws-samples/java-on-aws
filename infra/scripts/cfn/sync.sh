#!/bin/bash

# Workshop sync script
source "$(dirname "$0")/../lib/common.sh"

WORKSHOPS=("ide" "java-on-aws" "java-on-eks" "java-ai-agents" "java-spring-ai-agents")

log_info "Syncing CloudFormation templates and policies to workshop directories..."

for workshop in "${WORKSHOPS[@]}"; do
    target_dir="../$workshop/static"

    if [[ -d "$target_dir" ]]; then
        # Copy CloudFormation template with workshop-specific name
        cp "workshop-template.yaml" "$target_dir/$workshop-stack.yaml" || {
            log_error "Failed to copy template for $workshop"
            continue
        }
        log_success "Synced workshop-template.yaml to $workshop/static/$workshop-stack.yaml"

        # Copy IAM policy from resources directory
        if [[ -f "cdk/src/main/resources/iam-policy.json" ]]; then
            cp "cdk/src/main/resources/iam-policy.json" "$target_dir/policy.json" || {
                log_warning "Failed to copy policy for $workshop"
            }
            log_success "Synced iam-policy.json to $workshop/static/policy.json"
        else
            log_warning "Policy file cdk/src/main/resources/iam-policy.json not found"
        fi
    else
        log_warning "Directory $target_dir not found, skipping sync for $workshop"
    fi
done

log_success "All templates and policies synced successfully!"