#!/bin/bash
set -e

# Generate unique log group name with runtime timestamp
LOG_GROUP_NAME="ide-bootstrap-$(date +%Y%m%d-%H%M%S)"
echo "Bootstrap logs will be written to CloudWatch log group: $LOG_GROUP_NAME"

# Install and configure CloudWatch agent for logging
echo "Installing CloudWatch agent..."
yum install -y amazon-cloudwatch-agent

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

# Redirect all bootstrap output to log file and console
exec > >(tee -a /var/log/bootstrap.log)
exec 2>&1

echo "Bootstrap started at $(date) - Logging to $LOG_GROUP_NAME"

echo "Setting IDE password..."
export IDE_PASSWORD="${idePassword}"

echo "Setting profile variables..."
# Set some useful variables
export TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export AWS_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/dynamic/instance-identity/document | grep region | awk -F\" '{print $4}')
export EC2_PRIVATE_IP=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/local-ipv4)
export EC2_DOMAIN=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" -s http://169.254.169.254/latest/meta-data/public-hostname)
export EC2_URL="http://$EC2_DOMAIN"

# Get CloudFront domain
export IDE_DOMAIN=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Origins.Items[0].Id, 'IdeDistribution')].DomainName | [0]" --output text)

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
yum update -y

echo "Installing AWS CLI..."
curl -LSsf -o /tmp/aws-cli.zip https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip
unzip -q -d /tmp /tmp/aws-cli.zip
/tmp/aws/install --update
rm -rf /tmp/aws*

echo "export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)" | sudo tee -a /etc/profile.d/workshop.sh
source /etc/profile.d/workshop.sh

echo "Installing Docker..."
dnf install -y -q docker git jq >/dev/null
service docker start
usermod -aG docker ec2-user

echo "Installing code-server..."
codeServer=$(dnf list installed code-server 2>/dev/null | wc -l)
if [ "$codeServer" -eq "0" ]; then
  sudo -u ec2-user bash -c 'curl -fsSL https://code-server.dev/install.sh | sh -s -- --version 4.104.3'
  systemctl enable --now code-server@ec2-user
fi

sudo -u ec2-user bash -c 'mkdir -p ~/.config/code-server'
sudo -u ec2-user bash -c 'touch ~/.config/code-server/config.yaml'
tee /home/ec2-user/.config/code-server/config.yaml <<EOF
cert: false
auth: password
password: "$IDE_PASSWORD"
bind-addr: 127.0.0.1:8889
EOF

echo "Creating ~/environment folder..."
sudo -u ec2-user bash -c 'mkdir -p ~/environment'

echo "Configuring code-server..."
sudo -u ec2-user bash -c 'mkdir -p ~/.local/share/code-server/User'
sudo -u ec2-user bash -c 'touch ~/.local/share/code-server/User/settings.json'
tee /home/ec2-user/.local/share/code-server/User/settings.json <<EOF
{
  "extensions.autoUpdate": false,
  "extensions.autoCheckUpdates": false,
  "security.workspace.trust.enabled": false,
  "workbench.startupEditor": "terminal",
  "task.allowAutomaticTasks": "on",
  "telemetry.telemetryLevel": "off",
  "update.mode": "none"
}
EOF

sudo -u ec2-user bash -c 'touch ~/.local/share/code-server/User/keybindings.json'
tee /home/ec2-user/.local/share/code-server/User/keybindings.json << 'EOF'
[
  {
    "key": "shift+cmd+/",
    "command": "remote.tunnel.forwardCommandPalette"
  }
]
EOF

if [ ! -f "/home/ec2-user/.local/share/code-server/coder.json" ]; then
  sudo -u ec2-user bash -c 'touch ~/.local/share/code-server/coder.json'
  echo '{ "query": { "folder": "/home/ec2-user/environment" } }' > /home/ec2-user/.local/share/code-server/coder.json
fi

echo "Restarting code-server..."
systemctl restart code-server@ec2-user

echo "Installing Caddy..."
dnf copr enable -y -q @caddy/caddy epel-9-x86_64
dnf install -y -q caddy
systemctl enable --now caddy

tee /etc/caddy/Caddyfile <<EOF
:80 {
  handle /* {
    reverse_proxy 127.0.0.1:8889
  }
}
EOF

echo "Restarting caddy..."
systemctl restart caddy

echo "VS Code IDE setup completed successfully at $(date)"

# Clone workshop setup scripts from the main branch
echo "Cloning workshop setup scripts..."
cd /tmp
git clone https://github.com/aws-samples/java-on-aws.git workshop-setup
cd workshop-setup

# Make scripts executable
chmod +x infra/scripts/setup/*.sh

# Run the IDE setup script as ec2-user
echo "Running IDE setup script as ec2-user..."
sudo -u ec2-user bash infra/scripts/setup/ide.sh

echo "Bootstrap completed successfully at $(date)"

# Signal CloudFormation completion
/opt/aws/bin/cfn-signal -e $? --stack ${stackName} --resource IdeBootstrapWaitCondition --region ${awsRegion}