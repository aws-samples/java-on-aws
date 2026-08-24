#!/bin/bash

# Copies workshop-specific CloudFormation templates and policy files
# to sibling workshop repositories defined in infra/workshops.json.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

INFRA_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
REPO_ROOT="$(cd "$INFRA_DIR/.." && pwd)"
WORKSPACE_ROOT="$(dirname "$REPO_ROOT")"
CONFIG_FILE="$INFRA_DIR/workshops.json"
SHARED_POLICY_FILE="$INFRA_DIR/cdk/src/main/resources/iam-policy.json"
AGENTCORE_IDENTITY_POLICY_FILE="$INFRA_DIR/cdk/src/main/resources/agentcore-identity-policy.json"

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Workshop registry not found: $CONFIG_FILE"
    exit 1
fi
if [[ ! -f "$SHARED_POLICY_FILE" ]]; then
    log_error "Shared policy file not found: $SHARED_POLICY_FILE"
    exit 1
fi
if [[ ! -f "$AGENTCORE_IDENTITY_POLICY_FILE" ]]; then
    log_error "AgentCore Identity policy file not found: $AGENTCORE_IDENTITY_POLICY_FILE"
    exit 1
fi

all_templates=()
all_repositories=()
while IFS=$'\t' read -r template repository; do
    all_templates+=("$template")
    all_repositories+=("$repository")
done < <(jq -r '.workshops[] | [.template, .repository] | @tsv' "$CONFIG_FILE")

if [[ "${#all_templates[@]}" -eq 0 ]]; then
    log_error "No workshops configured in $CONFIG_FILE"
    exit 1
fi

echo ""
echo "Select template to sync:"
echo "  0) All templates"
for index in "${!all_templates[@]}"; do
    echo "  $((index + 1))) ${all_templates[$index]} -> ${all_repositories[$index]}"
done
echo ""
read -r -p "Enter choice [0-${#all_templates[@]}]: " choice

selected_indexes=()
if [[ "$choice" == "0" ]]; then
    selected_indexes=("${!all_templates[@]}")
elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#all_templates[@]} )); then
    selected_indexes=("$((choice - 1))")
else
    log_error "Invalid choice: $choice"
    exit 1
fi

log_info "Syncing CloudFormation templates and policies to workshop repositories..."
synced_count=0

for index in "${selected_indexes[@]}"; do
    template="${all_templates[$index]}"
    repository="${all_repositories[$index]}"
    target_dir="$WORKSPACE_ROOT/$repository/static"
    template_file="$INFRA_DIR/cfn/${template}-stack.yaml"

    if [[ ! -d "$target_dir" ]]; then
        log_info "Directory not found, skipping $repository: $target_dir"
        continue
    fi
    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        exit 1
    fi

    cp "$template_file" "$target_dir/workshop-stack.yaml" || {
        log_error "Failed to copy template for $template"
        exit 1
    }
    log_success "Synced $template_file to $repository/static/workshop-stack.yaml"

    cp "$SHARED_POLICY_FILE" "$target_dir/iam-policy.json" || {
        log_error "Failed to copy policy for $template"
        exit 1
    }
    log_success "Synced $SHARED_POLICY_FILE to $repository/static/iam-policy.json"

    if [[ "$template" == "java-ai-agents" || "$template" == "java-ai-agents-advanced" ]]; then
        cp "$AGENTCORE_IDENTITY_POLICY_FILE" "$target_dir/agentcore-identity-policy.json" || {
            log_error "Failed to copy AgentCore Identity policy for $template"
            exit 1
        }
        log_success "Synced $AGENTCORE_IDENTITY_POLICY_FILE to $repository/static/agentcore-identity-policy.json"
    fi

    synced_count=$((synced_count + 1))
done

if [[ "$synced_count" -eq 0 ]]; then
    log_warning "No workshop repositories were synchronized under $WORKSPACE_ROOT"
else
    log_success "Synced $synced_count workshop(s) successfully!"
fi
