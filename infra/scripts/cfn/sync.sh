#!/bin/bash

# Workshop sync script
# Copies workshop-specific CloudFormation templates and shared IAM policy to workshop directories
# Target directories are sibling folders to the repo: ../../java-on-aws/static, etc.
# Structure: workshops/java-on-aws/static, workshops/java-on-eks/static, workshops/java-on-aws (this repo)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

# Change to infra directory (script may be called from different locations)
cd "$SCRIPT_DIR/../.." || {
    log_error "Failed to change to infra directory"
    exit 1
}

WORKSHOPS=("java-on-aws-immersion-day" "java-on-amazon-eks" "java-spring-ai-agents" "java-ai-agents")

# Shared IAM policy file used by all workshops
SHARED_POLICY_FILE="cdk/src/main/resources/iam-policy.json"

if [[ ! -f "$SHARED_POLICY_FILE" ]]; then
    log_error "Shared policy file $SHARED_POLICY_FILE not found"
    exit 1
fi

# Display menu
echo ""
echo "Select template to sync:"
echo "  0) All templates"
echo "  1) java-on-aws-immersion-day"
echo "  2) java-on-amazon-eks"
echo "  3) java-spring-ai-agents"
echo "  4) java-ai-agents"
echo ""
read -p "Enter choice [0-4]: " choice

# Determine which workshops to sync
case $choice in
    0) selected_workshops=("${WORKSHOPS[@]}") ;;
    1) selected_workshops=("java-on-aws-immersion-day") ;;
    2) selected_workshops=("java-on-amazon-eks") ;;
    3) selected_workshops=("java-spring-ai-agents") ;;
    4) selected_workshops=("java-ai-agents") ;;
    *)
        log_error "Invalid choice: $choice"
        exit 1
        ;;
esac

log_info "Syncing CloudFormation templates and policies to workshop directories..."

synced_count=0

for workshop in "${selected_workshops[@]}"; do
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

        # Copy shared IAM policy -> iam-policy.json
        cp "$SHARED_POLICY_FILE" "$target_dir/iam-policy.json" || {
            log_error "Failed to copy policy for $workshop"
            exit 1
        }
        log_success "Synced $SHARED_POLICY_FILE to $workshop/static/iam-policy.json"

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
