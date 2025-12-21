#!/bin/bash
set -e

# Full bootstrap script - called by minimal UserData
# Parameters: GIT_BRANCH TEMPLATE_TYPE

# Parse parameters
GIT_BRANCH="$1"
TEMPLATE_TYPE="$2"

# Use PREFIX from environment, default to "workshop" if not set
PREFIX="${PREFIX:-workshop}"

echo "Full bootstrap started at $(date)"
echo "Parameters: GIT_BRANCH=$GIT_BRANCH, TEMPLATE_TYPE=$TEMPLATE_TYPE, PREFIX=$PREFIX"

# Retry utility function
# Usage: retry_command <attempts> <delay> <fail_mode> <tool_name> <command...>
# fail_mode: "FAIL" (exit on failure), "LOG" (log and continue)
retry_command() {
    local max_attempts="$1"
    local delay="$2"
    local fail_mode="$3"
    local tool_name="$4"
    shift 4
    local cmd="$*"

    for attempt in $(seq 1 $max_attempts); do
        if eval "$cmd"; then
            echo "✅ Success: $tool_name"
            return 0
        fi
        echo "❌ Failed attempt $attempt/$max_attempts: $tool_name"

        if [ $attempt -lt $max_attempts ]; then
            echo "Waiting ${delay}s before retry..."
            sleep $delay
        fi
    done

    if [ "$fail_mode" = "FAIL" ]; then
        echo "💥 FATAL: $tool_name failed after $max_attempts attempts"
        exit 1
    else
        echo "⚠️  WARNING: $tool_name failed after $max_attempts attempts (continuing)"
        return 1
    fi
}

# Helper function to install and get version
install_with_version() {
    local tool_name="$1"
    local install_cmd="$2"
    local version_cmd="$3"
    local fail_mode="${4:-FAIL}"

    if eval "$install_cmd"; then
        if [ -n "$version_cmd" ]; then
            local version=$(eval "$version_cmd" 2>/dev/null | head -1 || echo "unknown")
            echo "✅ Success: $tool_name $version"
        else
            echo "✅ Success: $tool_name"
        fi
        return 0
    else
        if [ "$fail_mode" = "FAIL" ]; then
            echo "💥 FATAL: $tool_name failed"
            exit 1
        else
            echo "⚠️  WARNING: $tool_name failed (continuing)"
            return 1
        fi
    fi
}

# Convenience functions for different retry policies
retry_critical() { retry_command 5 5 "FAIL" "$@"; }
retry_optional() { retry_command 5 5 "LOG" "$@"; }

echo "$(date '+%Y-%m-%d %H:%M:%S') - Updating system packages..."
dnf update -y -q

echo "$(date '+%Y-%m-%d %H:%M:%S') - Installing jq (required for secret parsing)..."
dnf install -y -q jq

echo "$(date '+%Y-%m-%d %H:%M:%S') - Installing AWS CLI..."
install_with_version "AWS CLI" "curl -LSsf -o /tmp/aws-cli.zip https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip && rm -rf /tmp/aws && unzip -q -d /tmp /tmp/aws-cli.zip && /tmp/aws/install --update && rm -rf /tmp/aws*" "aws --version | awk '{print \$1\" \"\$2}'"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Installing CloudFormation helper scripts..."
install_with_version "CloudFormation helper scripts" "dnf install -y aws-cfn-bootstrap" "rpm -q aws-cfn-bootstrap --queryformat '%{VERSION}'"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Fetching IDE password from Secrets Manager..."
IDE_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "${PREFIX}-ide-password" --query SecretString --output text | jq -r .password)
if [ -z "$IDE_PASSWORD" ] || [ "$IDE_PASSWORD" = "null" ]; then
    echo "ERROR: Failed to retrieve IDE password from Secrets Manager"
    exit 1
fi
export IDE_PASSWORD

echo "Setting profile variables..."
# Set some useful variables
export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export AWS_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')

# Now that we have AWS_REGION, set up error trap for CloudFormation signaling
trap 'echo "Bootstrap failed at line $LINENO"; /opt/aws/bin/cfn-signal -e 1 "$WAIT_CONDITION_HANDLE_URL" 2>/dev/null || true; exit 1' ERR

export EC2_PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)
export EC2_DOMAIN=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-hostname)
export EC2_URL="http://$EC2_DOMAIN"

# Get CloudFront domain for IDE access
if ! IDE_DOMAIN=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Origins.Items[0].Id, 'IdeDistribution')].DomainName | [0]" --output text 2>/dev/null); then
    echo "Warning: Could not retrieve CloudFront domain, IDE_DOMAIN will be empty"
    IDE_DOMAIN=""
fi
export IDE_DOMAIN

# IDE type - from CDK parameter via UserData, default to code-editor
IDE_TYPE="${IDE_TYPE:-code-editor}"
echo "IDE type: $IDE_TYPE"

# Set code alias based on IDE type
if [ "$IDE_TYPE" = "code-editor" ]; then
    CODE_ALIAS='alias code="/home/ec2-user/.local/bin/code-editor-server"'
else
    CODE_ALIAS='alias code="code-server"'
fi

tee /etc/profile.d/workshop.sh <<EOF
export AWS_REGION="$AWS_REGION"
export AWS_DEFAULT_REGION="$AWS_REGION"
export EC2_PRIVATE_IP="$EC2_PRIVATE_IP"
export EC2_DOMAIN="$EC2_DOMAIN"
export EC2_URL="$EC2_URL"

export IDE_DOMAIN="$IDE_DOMAIN"
export IDE_URL="https://$IDE_DOMAIN"
export IDE_PASSWORD="$IDE_PASSWORD"

$CODE_ALIAS
EOF

source /etc/profile.d/workshop.sh

echo "export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)" | tee -a /etc/profile.d/workshop.sh
echo "export AWS_ACCOUNT_ID=\$ACCOUNT_ID" | tee -a /etc/profile.d/workshop.sh
source /etc/profile.d/workshop.sh

echo "Setting PS1..."
tee /etc/profile.d/custom_prompt.sh <<EOF
#!/bin/sh
export PROMPT_COMMAND='export PS1="\u:\w:$ "'
EOF

echo "Generating SSH key..."
sudo -u ec2-user bash -c "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -m pem <<< y"

echo "Bootstrap script running from: $(pwd)"
echo "Using git branch: $GIT_BRANCH"

# Ensure we're in the right directory
if [ ! -f "infra/scripts/ide/bootstrap.sh" ]; then
    echo "ERROR: Not in the correct repository directory"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Running IDE setup (${IDE_TYPE})..."
bash infra/scripts/ide/${IDE_TYPE}.sh

echo "$(date '+%Y-%m-%d %H:%M:%S') - Installing development tools..."
sudo -H -i -u ec2-user bash -c "$(pwd)/infra/scripts/ide/tools.sh"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Running post-deploy for template type: $TEMPLATE_TYPE"

# Run template-specific post-deploy script
if [ -f "infra/scripts/templates/${TEMPLATE_TYPE}.sh" ]; then
    sudo -H -i -u ec2-user bash -c "$(pwd)/infra/scripts/templates/${TEMPLATE_TYPE}.sh"
else
    echo "ERROR: Template script infra/scripts/templates/${TEMPLATE_TYPE}.sh not found"
    exit 1
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Bootstrap completed successfully"

# Create IDE bootstrap summary for easy reference
echo "Creating IDE bootstrap summary..."
grep "✅ Success:" /var/log/bootstrap.log | sudo -u ec2-user tee /home/ec2-user/workshop-ide-bootstrap.log >/dev/null
sudo -u ec2-user chmod 644 /home/ec2-user/workshop-ide-bootstrap.log
echo "Bootstrap summary saved to ~/workshop-ide-bootstrap.log"

# Signal CloudFormation completion
/opt/aws/bin/cfn-signal -e $? "$WAIT_CONDITION_HANDLE_URL"