#!/bin/bash

# Template generation script
source "$(dirname "$0")/../lib/common.sh"

log_info "Generating unified CloudFormation template..."

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

# Get template type from environment or default to base
TEMPLATE_TYPE="${TEMPLATE_TYPE:-base}"
log_info "Using template type: $TEMPLATE_TYPE"

# Generate CloudFormation template
log_info "Synthesizing CloudFormation template..."
cdk synth WorkshopStack --yaml --path-metadata false --version-reporting false --context git.branch="$GIT_BRANCH" --context template.type="$TEMPLATE_TYPE" > ../workshop-template.yaml || {
    log_error "CDK synthesis failed"
    exit 1
}

# Apply CloudFormation substitutions and remove CDK dependencies
log_info "Applying CloudFormation substitutions..."
sed -i '' 's/arn:aws:iam::{{\.AccountId}}:/!Sub arn:aws:iam::${AWS::AccountId}:/g' ../workshop-template.yaml

# Remove CDK bootstrap parameter to make template self-sufficient
log_info "Removing CDK bootstrap dependencies..."
sed -i '' '/BootstrapVersion:/,/Description.*cdk:skip/d' ../workshop-template.yaml

log_success "Generated workshop-template.yaml successfully"