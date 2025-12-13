#!/bin/bash
set -e

# Full bootstrap script - called by minimal UserData
# Parameters: IDE_PASSWORD GIT_BRANCH STACK_NAME AWS_REGION TEMPLATE_TYPE

# Parse parameters
IDE_PASSWORD="$1"
GIT_BRANCH="$2"
STACK_NAME="$3"
AWS_REGION="$4"
TEMPLATE_TYPE="$5"

echo "Full bootstrap started at $(date)"
echo "Parameters: GIT_BRANCH=$GIT_BRANCH, TEMPLATE_TYPE=$TEMPLATE_TYPE, AWS_REGION=$AWS_REGION"

# CloudWatch logging is already set up by UserData script

# Retry utility function
# Usage: retry_command <attempts> <delay> <fail_mode> <command...>
# fail_mode: "FAIL" (exit on failure), "LOG" (log and continue)
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    local fail_mode="$3"
    shift 3
    local cmd="$*"

    for attempt in $(seq 1 $max_attempts); do
        echo "Attempt $attempt/$max_attempts: $cmd"
        if eval "$cmd"; then
            echo "✅ Success on attempt $attempt"
            return 0
        fi
        echo "❌ Failed on attempt $attempt"

        if [ $attempt -lt $max_attempts ]; then
            echo "Waiting ${delay}s before retry..."
            sleep $delay
        fi
    done

    if [ "$fail_mode" = "FAIL" ]; then
        echo "💥 FATAL: Command failed after $max_attempts attempts: $cmd"
        exit 1
    else
        echo "⚠️  WARNING: Command failed after $max_attempts attempts (continuing): $cmd"
        return 1
    fi
}

# Convenience functions for different retry policies
retry_critical() { retry_command 5 5 "FAIL" "$@"; }
retry_optional() { retry_command 5 5 "LOG" "$@"; }

echo "Setting IDE password..."
export IDE_PASSWORD="$IDE_PASSWORD"

echo "Setting profile variables..."
# Set some useful variables
export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export AWS_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')
export EC2_PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)
export EC2_DOMAIN=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-hostname)
export EC2_URL="http://$EC2_DOMAIN"

# Get CloudFront domain for IDE access
if ! IDE_DOMAIN=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Origins.Items[0].Id, 'IdeDistribution')].DomainName | [0]" --output text 2>/dev/null); then
    echo "Warning: Could not retrieve CloudFront domain, IDE_DOMAIN will be empty"
    IDE_DOMAIN=""
fi
export IDE_DOMAIN

tee /etc/profile.d/workshop.sh <<EOF
export AWS_REGION="$AWS_REGION"
export AWS_DEFAULT_REGION="$AWS_REGION"
export EC2_PRIVATE_IP="$EC2_PRIVATE_IP"
export EC2_DOMAIN="$EC2_DOMAIN"
export EC2_URL="$EC2_URL"

export IDE_DOMAIN="$IDE_DOMAIN"
export IDE_URL="https://$IDE_DOMAIN"
export IDE_PASSWORD="$IDE_PASSWORD"

alias code="code-server"
EOF

source /etc/profile.d/workshop.sh

echo "Setting PS1..."
tee /etc/profile.d/custom_prompt.sh <<EOF
#!/bin/sh
export PROMPT_COMMAND='export PS1="\u:\w:$ "'
EOF

echo "Generating SSH key..."
sudo -u ec2-user bash -c "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -m pem <<< y"

echo "Updating system packages..."
dnf update -y

echo "Installing AWS CLI..."
retry_critical "curl -LSsf -o /tmp/aws-cli.zip https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip && unzip -q -d /tmp /tmp/aws-cli.zip && /tmp/aws/install --update && rm -rf /tmp/aws*"

echo "export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)" | sudo tee -a /etc/profile.d/workshop.sh
source /etc/profile.d/workshop.sh

echo "Installing git..."
retry_critical "dnf install -y -q git >/dev/null"

# Clone workshop setup scripts
echo "Cloning workshop setup scripts..."
cd /tmp
retry_critical "git clone https://github.com/aws-samples/java-on-aws.git workshop-setup"
cd workshop-setup
retry_critical "git checkout ${GIT_BRANCH:-main}"

# Make scripts executable
chmod +x infra/scripts/ide/*.sh

# Run VS Code setup
echo "Running VS Code setup..."
export VSCODE_EXTENSIONS="$VSCODE_EXTENSIONS"
bash infra/scripts/ide/vscode.sh

echo "Running setup for template type: $TEMPLATE_TYPE"

# Run template-specific setup script
if [ -f "infra/scripts/ide/${TEMPLATE_TYPE}.sh" ]; then
    sudo -u ec2-user bash "infra/scripts/ide/${TEMPLATE_TYPE}.sh"
else
    echo "Warning: Template script infra/scripts/ide/${TEMPLATE_TYPE}.sh not found, skipping setup"
fi

echo "Bootstrap completed successfully at $(date)"

# Signal CloudFormation completion
/opt/aws/bin/cfn-signal -e $? --stack "$STACK_NAME" --resource IdeBootstrapWaitCondition --region "$AWS_REGION"