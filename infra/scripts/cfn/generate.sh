#!/bin/bash

# Template generation script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/common.sh"

INFRA_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$INFRA_DIR/workshops.json"
CDK_DIR="$INFRA_DIR/cdk"

if [[ ! -f "$CONFIG_FILE" ]]; then
    log_error "Workshop registry not found: $CONFIG_FILE"
    exit 1
fi

all_templates=()
while IFS= read -r template; do
    all_templates+=("$template")
done < <(jq -r '.workshops[].template' "$CONFIG_FILE")

if [[ "${#all_templates[@]}" -eq 0 ]]; then
    log_error "No workshops configured in $CONFIG_FILE"
    exit 1
fi

echo ""
echo "Select template to generate:"
echo "  0) All templates"
for index in "${!all_templates[@]}"; do
    echo "  $((index + 1))) ${all_templates[$index]}"
done
echo ""
read -r -p "Enter choice [0-${#all_templates[@]}]: " choice

if [[ "$choice" == "0" ]]; then
    templates=("${all_templates[@]}")
elif [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#all_templates[@]} )); then
    templates=("${all_templates[$((choice - 1))]}")
else
    log_error "Invalid choice: $choice"
    exit 1
fi

cd "$CDK_DIR" || {
    log_error "Failed to change to CDK directory"
    exit 1
}

log_info "Generating CloudFormation templates..."
log_info "Building CDK project..."
mvn clean package -q || {
    log_error "Maven build failed"
    exit 1
}

GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
log_info "Using git branch: $GIT_BRANCH"
mkdir -p ../cfn

generate_template() {
    local template_type=$1
    local output_file="../cfn/${template_type}-stack.yaml"

    log_info "Generating $template_type template..."
    export TEMPLATE_TYPE="$template_type"

    cdk synth WorkshopStack --path-metadata false --version-reporting false \
        --context git.branch="$GIT_BRANCH" --context template.type="$template_type" > "$output_file" || {
        log_error "CDK synthesis failed for $template_type"
        return 1
    }

    log_info "Processing $template_type template..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' 's/arn:aws:iam::{{\.AccountId}}:/!Sub arn:aws:iam::${AWS::AccountId}:/g' "$output_file"
        sed -i '' '/BootstrapVersion:/,/Description.*cdk:skip/d' "$output_file"
    else
        sed -i 's/arn:aws:iam::{{\.AccountId}}:/!Sub arn:aws:iam::${AWS::AccountId}:/g' "$output_file"
        sed -i '/BootstrapVersion:/,/Description.*cdk:skip/d' "$output_file"
    fi

    log_info "Sorting keys in $template_type template..."
    yq -i 'sort_keys(..)' "$output_file" || {
        log_error "Failed to sort keys in $output_file"
        return 1
    }

    log_success "Generated $template_type template: $output_file"
}

for template in "${templates[@]}"; do
    generate_template "$template"
done

log_success "CloudFormation template generation complete"
