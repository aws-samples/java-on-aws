#!/bin/bash
set -e

# IDE setup script - runs as ec2-user
# Note: All output is automatically logged to CloudWatch via the bootstrap process

echo "Starting IDE setup at $(date)"
echo "IDE setup logs are being written to CloudWatch log group: ${LOG_GROUP_NAME:-ide-bootstrap}"

# Update system packages
echo "Updating system packages..."
sudo yum update -y

# Create environment folder for workshop
echo "Creating ~/environment folder..."
mkdir -p ~/environment
echo "Environment folder created at: $(pwd)/environment"

# Log completion
echo "IDE setup completed successfully at $(date)"
echo "Ready for workshop activities!"