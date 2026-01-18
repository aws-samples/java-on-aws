#!/bin/bash

# Template generation script
source "$(dirname "$0")/../lib/common.sh"

# Change to CDK directory
cd "$(dirname "$0")/../../cdk" || {
    log_error "Failed to change to CDK directory"
    exit 1
}

# Display menu
echo ""
echo "Select template to generate:"
echo "  0) All templates"
echo "  1) java-on-aws-immersion-day"
echo "  2) java-on-amazon-eks"
echo "  3) java-spring-ai-agents"
echo "  4) java-ai-agents"
echo ""
read -p "Enter choice [0-4]: " choice

# Determine which templates to generate
case $choice in
    0) templates=("java-on-aws-immersion-day" "java-on-amazon-eks" "java-spring-ai-agents" "java-ai-agents") ;;
    1) templates=("java-on-aws-immersion-day") ;;
    2) templates=("java-on-amazon-eks") ;;
    3) templates=("java-spring-ai-agents") ;;
    4) templates=("java-ai-agents") ;;
    *)
        log_error "Invalid choice: $choice"
        exit 1
        ;;
esac

log_info "Generating CloudFormation templates..."

# Clean and build Maven project
log_info "Building CDK project..."
mvn clean package -q || {
    log_error "Maven build failed"
    exit 1
}

# Get current git branch
GIT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
log_info "Using git branch: $GIT_BRANCH"

# Create cfn directory if it doesn't exist
mkdir -p ../cfn

# Function to generate and process template
generate_template() {
    local template_type=$1
    local output_file="../cfn/${template_type}-stack.yaml"

    log_info "Generating $template_type template..."

    # Set environment variable for CDK
    export TEMPLATE_TYPE="$template_type"

    # Generate CloudFormation template
    cdk synth WorkshopStack --yaml --path-metadata false --version-reporting false --context git.branch="$GIT_BRANCH" --context template.type="$template_type" > "$output_file" || {
        log_error "CDK synthesis failed for $template_type"
        return 1
    }

    # Apply CloudFormation substitutions and remove CDK dependencies
    log_info "Processing $template_type template..."
    if [[ -f "$output_file" ]]; then
        # Check if we're on macOS or Linux for sed syntax
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' 's/arn:aws:iam::{{\.AccountId}}:/!Sub arn:aws:iam::${AWS::AccountId}:/g' "$output_file"
            sed -i '' '/BootstrapVersion:/,/Description.*cdk:skip/d' "$output_file"
        else
            sed -i 's/arn:aws:iam::{{\.AccountId}}:/!Sub arn:aws:iam::${AWS::AccountId}:/g' "$output_file"
            sed -i '/BootstrapVersion:/,/Description.*cdk:skip/d' "$output_file"
        fi
    else
        log_error "Template file $output_file was not created"
        return 1
    fi

    # Sort YAML keys for deterministic output
    log_info "Sorting keys in $template_type template..."
    yq -i 'sort_keys(..)' "$output_file" || {
        log_error "Failed to sort keys in $output_file"
        return 1
    }

    log_success "Generated $template_type template: $output_file"
}

# Generate selected templates
for template in "${templates[@]}"; do
    generate_template "$template"
done

log_success "CloudFormation template generation complete"
