#!/bin/bash
set -e

GIT_BRANCH="$1"
TEMPLATE_TYPE="$2"
PREFIX="${PREFIX:-workshop}"

echo "Full bootstrap started at $(date)"
echo "Parameters: GIT_BRANCH=$GIT_BRANCH, TEMPLATE_TYPE=$TEMPLATE_TYPE, PREFIX=$PREFIX"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

log_info "Updating system packages..."
dnf update -y -q

log_info "Installing jq and Docker..."
dnf install -y -q jq docker
service docker start
usermod -aG docker ec2-user

log_info "Installing AWS CLI..."
install_with_version "AWS CLI" \
    "curl -LSsf -o /tmp/aws-cli.zip https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip && rm -rf /tmp/aws && unzip -q -d /tmp /tmp/aws-cli.zip && /tmp/aws/install --update && rm -rf /tmp/aws*" \
    "aws --version | awk '{print \$1\" \"\$2}'"

log_info "Installing CloudFormation helper scripts..."
install_with_version "CloudFormation helper scripts" \
    "dnf install -y aws-cfn-bootstrap" \
    "rpm -q aws-cfn-bootstrap --queryformat '%{VERSION}'"

log_info "Fetching IDE password from Secrets Manager..."
IDE_PASSWORD=$(aws secretsmanager get-secret-value --secret-id "${PREFIX}-ide-password" --query SecretString --output text | jq -r .password)
if [ -z "$IDE_PASSWORD" ] || [ "$IDE_PASSWORD" = "null" ]; then
    echo "ERROR: Failed to retrieve IDE password from Secrets Manager"
    exit 1
fi
export IDE_PASSWORD

export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export AWS_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')

trap 'echo "Bootstrap failed at line $LINENO"; /opt/aws/bin/cfn-signal -e 1 "$WAIT_CONDITION_HANDLE_URL" 2>/dev/null || true; exit 1' ERR

export EC2_PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)
export EC2_DOMAIN=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-hostname)
export EC2_URL="http://$EC2_DOMAIN"

if ! IDE_DOMAIN=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Origins.Items[0].Id, 'IdeDistribution')].DomainName | [0]" --output text 2>/dev/null); then
    echo "Warning: Could not retrieve CloudFront domain, IDE_DOMAIN will be empty"
    IDE_DOMAIN=""
fi
export IDE_DOMAIN

IDE_TYPE="${IDE_TYPE:-code-editor}"
echo "IDE type: $IDE_TYPE"

if [ "$IDE_TYPE" = "code-editor" ]; then
    CODE_ALIAS='alias code="/home/ec2-user/.local/bin/code-editor-server"'
else
    CODE_ALIAS='alias code="code-server"'
fi

ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)

tee /etc/profile.d/workshop.sh <<EOF
export AWS_REGION="$AWS_REGION"
export AWS_DEFAULT_REGION="$AWS_REGION"
export ACCOUNT_ID="$ACCOUNT_ID"
export AWS_ACCOUNT_ID="$ACCOUNT_ID"
export EC2_PRIVATE_IP="$EC2_PRIVATE_IP"
export EC2_DOMAIN="$EC2_DOMAIN"
export EC2_URL="$EC2_URL"
export IDE_DOMAIN="$IDE_DOMAIN"
export IDE_URL="https://$IDE_DOMAIN"
export IDE_PASSWORD="$IDE_PASSWORD"
$CODE_ALIAS
EOF

source /etc/profile.d/workshop.sh

tee /etc/profile.d/custom_prompt.sh <<EOF
#!/bin/sh
export PROMPT_COMMAND='export PS1="\u:\w:$ "'
EOF

sudo -u ec2-user bash -c "ssh-keygen -t rsa -N '' -f ~/.ssh/id_rsa -m pem <<< y"

if [ ! -f "infra/scripts/ide/bootstrap.sh" ]; then
    echo "ERROR: Not in the correct repository directory"
    exit 1
fi

log_info "Running IDE setup (${IDE_TYPE})..."
bash infra/scripts/ide/${IDE_TYPE}.sh

log_info "Installing development tools..."
sudo -H -i -u ec2-user bash -c "$(pwd)/infra/scripts/ide/tools.sh"

log_info "Running post-deploy for template type: $TEMPLATE_TYPE"
if [ -f "infra/scripts/templates/${TEMPLATE_TYPE}.sh" ]; then
    sudo -H -i -u ec2-user bash -c "$(pwd)/infra/scripts/templates/${TEMPLATE_TYPE}.sh"
else
    echo "ERROR: Template script infra/scripts/templates/${TEMPLATE_TYPE}.sh not found"
    exit 1
fi

log_info "Bootstrap completed successfully"

grep "✅ Success:" /var/log/bootstrap.log | sudo -u ec2-user tee /home/ec2-user/workshop-ide-bootstrap.log >/dev/null
sudo -u ec2-user chmod 644 /home/ec2-user/workshop-ide-bootstrap.log

/opt/aws/bin/cfn-signal -e $? "$WAIT_CONDITION_HANDLE_URL"
