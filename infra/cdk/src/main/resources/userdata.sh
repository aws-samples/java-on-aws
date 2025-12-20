#!/bin/bash
set -e

# Minimal EC2 UserData script - downloads and runs full bootstrap
# This keeps UserData under size limits while allowing unlimited bootstrap size

# Configuration from CDK
export GIT_BRANCH="${GIT_BRANCH}"
export AWS_REGION="${AWS_REGION}"
export TEMPLATE_TYPE="${TEMPLATE_TYPE}"
export ARCH="${ARCH}"
export IDE_TYPE="${IDE_TYPE}"
export WAIT_CONDITION_HANDLE_URL="${WAIT_CONDITION_HANDLE_URL}"
export PREFIX="${PREFIX}"

# Setup logging - use PREFIX for log group name
LOG_GROUP_NAME="${PREFIX}-ide-bootstrap-$(date +%Y%m%d-%H%M%S)"
echo "Bootstrap logs will be written to CloudWatch log group: $LOG_GROUP_NAME"

# Install CloudWatch agent for logging
dnf install -y amazon-cloudwatch-agent

# Create CloudWatch agent configuration
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json << EOF
{
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/bootstrap.log",
            "log_group_name": "$LOG_GROUP_NAME",
            "log_stream_name": "{instance_id}",
            "retention_in_days": 7
          }
        ]
      }
    }
  }
}
EOF

# Start CloudWatch agent
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s

# Redirect all output to log file and console
exec > >(tee -a /var/log/bootstrap.log)
exec 2>&1

echo "UserData started at $(date) - Logging to $LOG_GROUP_NAME"

# Set up error trap for UserData failures (before bootstrap.sh takes over)
trap 'echo "UserData failed at line $LINENO"; /opt/aws/bin/cfn-signal -e 1 "${WAIT_CONDITION_HANDLE_URL}" 2>/dev/null || true; exit 1' ERR

# Install git (required for cloning repository)
echo "Installing git..."
dnf install -y git

# Clone repository to ec2-user home directory
clone_repository() {
    local max_attempts=5
    local delay=5

    for attempt in $(seq 1 $max_attempts); do
        echo "Clone attempt $attempt of $max_attempts"

        # Remove existing directory if it exists
        sudo -u ec2-user rm -rf /home/ec2-user/java-on-aws

        # Clone as ec2-user to their home directory
        if sudo -u ec2-user git clone https://github.com/aws-samples/java-on-aws.git /home/ec2-user/java-on-aws; then
            # Checkout the correct branch as ec2-user
            if sudo -u ec2-user bash -c "cd /home/ec2-user/java-on-aws && git checkout $GIT_BRANCH"; then
                echo "Successfully cloned repository and checked out branch $GIT_BRANCH on attempt $attempt"
                return 0
            else
                echo "Failed to checkout branch $GIT_BRANCH on attempt $attempt"
            fi
        else
            echo "Failed to clone repository on attempt $attempt"
        fi

        if [ $attempt -lt $max_attempts ]; then
            echo "Clone failed on attempt $attempt, waiting ${delay}s before retry..."
            sleep $delay
        fi
    done

    echo "All clone attempts failed after $max_attempts tries"
    return 1
}

if clone_repository; then
    # Make scripts executable
    sudo -u ec2-user chmod +x /home/ec2-user/java-on-aws/infra/scripts/ide/*.sh

    echo "Executing full bootstrap script..."
    # Run bootstrap script as root from the cloned directory
    if cd /home/ec2-user/java-on-aws && WAIT_CONDITION_HANDLE_URL="${WAIT_CONDITION_HANDLE_URL}" infra/scripts/ide/bootstrap.sh "$GIT_BRANCH" "$TEMPLATE_TYPE"; then
        echo "Bootstrap completed successfully"
        # Bootstrap script already signaled success
    else
        echo "FATAL: Bootstrap script failed"
        /opt/aws/bin/cfn-signal -e 1 "${WAIT_CONDITION_HANDLE_URL}"
        exit 1
    fi
else
    echo "FATAL: Could not clone repository"
    /opt/aws/bin/cfn-signal -e 1 "${WAIT_CONDITION_HANDLE_URL}"
    exit 1
fi