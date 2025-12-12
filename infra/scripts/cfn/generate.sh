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

# Generate CloudFormation template
log_info "Synthesizing CloudFormation template..."
cdk synth WorkshopStack --yaml --path-metadata false --version-reporting false > ../workshop-template.yaml || {
    log_error "CDK synthesis failed"
    exit 1
}

# Apply CloudFormation substitutions (same as existing infrastructure)
log_info "Applying CloudFormation substitutions..."
sed -i '' 's/arn:aws:iam::{{\.AccountId}}:/!Sub arn:aws:iam::${AWS::AccountId}:/g' ../workshop-template.yaml

log_success "Generated workshop-template.yaml successfully"