#!/bin/bash

# Template generation script
source "$(dirname "$0")/../lib/common.sh"

log_info "Generating CloudFormation templates..."

# Change to CDK directory
cd "$(dirname "$0")/../../cdk" || {
    log_error "Failed to change to CDK directory"
    exit 1
}

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
    local output_file=$2

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

    log_success "Generated $template_type template: $output_file"
}

# Generate base template (IDE only)
generate_template "base" "../cfn/base-stack.yaml"

# Generate java-on-aws-immersion-day template (IDE + Database + EKS + Roles)
generate_template "java-on-aws-immersion-day" "../cfn/java-on-aws-immersion-day-stack.yaml"

# Generate java-on-amazon-eks template (same as java-on-aws-immersion-day)
generate_template "java-on-amazon-eks" "../cfn/java-on-amazon-eks-stack.yaml"

# Generate java-spring-ai-agents template (same as java-on-aws-immersion-day)
generate_template "java-spring-ai-agents" "../cfn/java-spring-ai-agents-stack.yaml"

log_success "All CloudFormation templates generated successfully"