#!/bin/bash
set -e

# Minimal EC2 UserData script - downloads and runs full bootstrap
# This keeps UserData under size limits while allowing unlimited bootstrap size

# Configuration from CDK
GIT_BRANCH="${gitBranch:-main}"
IDE_PASSWORD="${idePassword}"
STACK_NAME="${stackName}"
AWS_REGION="${awsRegion}"
TEMPLATE_TYPE="${templateType:-base}"
VSCODE_EXTENSIONS="${vscodeExtensions:-}"

# Setup logging
LOG_GROUP_NAME="ide-bootstrap-$(date +%Y%m%d-%H%M%S)"
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

# Download and run full bootstrap script with retry logic
download_bootstrap() {
    local urls=(
        "https://raw.githubusercontent.com/aws-samples/java-on-aws/${GIT_BRANCH}/infra/scripts/ide/bootstrap.sh"
        "https://github.com/aws-samples/java-on-aws/raw/${GIT_BRANCH}/infra/scripts/ide/bootstrap.sh"
    )
    local max_attempts=5
    local delay=5

    for attempt in $(seq 1 $max_attempts); do
        echo "Download attempt $attempt of $max_attempts"

        for url in "${urls[@]}"; do
            echo "Trying to download bootstrap from: $url"
            if curl -fsSL --connect-timeout 30 --max-time 60 "$url" -o /tmp/bootstrap.sh; then
                echo "Successfully downloaded bootstrap script on attempt $attempt"
                return 0
            fi
            echo "Failed to download from: $url"
        done

        if [ $attempt -lt $max_attempts ]; then
            echo "All URLs failed on attempt $attempt, waiting ${delay}s before retry..."
            sleep $delay
        fi
    done

    echo "All download attempts failed after $max_attempts tries"
    return 1
}

if download_bootstrap; then
    chmod +x /tmp/bootstrap.sh
    echo "Executing full bootstrap script..."
    export VSCODE_EXTENSIONS="$VSCODE_EXTENSIONS"
    if /tmp/bootstrap.sh "$IDE_PASSWORD" "$GIT_BRANCH" "$STACK_NAME" "$AWS_REGION" "$TEMPLATE_TYPE"; then
        echo "Bootstrap completed successfully"
        /opt/aws/bin/cfn-signal -e 0 --stack "$STACK_NAME" --resource IdeBootstrapWaitCondition --region "$AWS_REGION"
    else
        echo "FATAL: Bootstrap script failed"
        /opt/aws/bin/cfn-signal -e 1 --stack "$STACK_NAME" --resource IdeBootstrapWaitCondition --region "$AWS_REGION"
        exit 1
    fi
else
    echo "FATAL: Could not download bootstrap script from any source"
    /opt/aws/bin/cfn-signal -e 1 --stack "$STACK_NAME" --resource IdeBootstrapWaitCondition --region "$AWS_REGION"
    exit 1
fi