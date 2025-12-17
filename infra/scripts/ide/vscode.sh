#!/bin/bash
set -e

# =============================================================================
# VERSION DEFINITIONS (managed by Renovate)
# =============================================================================

# VS Code Server version
VSCODE_VERSION="4.106.3"

# =============================================================================

# Source common IDE settings (extensions, workspace config)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/ide-settings.sh"

# =============================================================================

# Import retry functions from bootstrap (if available, fallback to direct execution)
retry_critical() {
    if command -v retry_command >/dev/null 2>&1; then
        retry_command 5 5 "FAIL" "$@"
    else
        local tool_name="$1"
        shift
        if eval "$*"; then
            echo "✅ Success: $tool_name"
        else
            echo "💥 FATAL: $tool_name failed"
            exit 1
        fi
    fi
}
retry_optional() {
    if command -v retry_command >/dev/null 2>&1; then
        retry_command 5 5 "LOG" "$@"
    else
        local tool_name="$1"
        shift
        if eval "$*"; then
            echo "✅ Success: $tool_name"
        else
            echo "⚠️  Warning: $tool_name failed (continuing)"
        fi
    fi
}

# Helper function to create user files
setup_user_file() {
    local file_path="$1"
    local content="$2"
    sudo -u ec2-user mkdir -p "$(dirname "$file_path")"
    sudo -u ec2-user tee "$file_path" >/dev/null <<< "$content"
}

# Helper function to run commands as ec2-user
run_as_user() {
    sudo -u ec2-user bash -c "$1"
}

echo "$(date '+%Y-%m-%d %H:%M:%S') - Installing code-server..."
codeServer=$(dnf list installed code-server 2>/dev/null | wc -l)
if [ "$codeServer" -eq "0" ]; then
  # Install as ec2-user with retry logic - pass version as environment variable
  retry_critical "VS Code Server ${VSCODE_VERSION}" "sudo -u ec2-user bash -c 'curl -fsSL https://code-server.dev/install.sh | sh -s -- --version $VSCODE_VERSION'"
  retry_critical "VS Code Server service" "systemctl enable --now code-server@ec2-user"
fi

# Configure code-server
setup_user_file "/home/ec2-user/.config/code-server/config.yaml" "cert: false
auth: password
password: \"$IDE_PASSWORD\"
bind-addr: 127.0.0.1:8889"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Creating ~/environment folder..."
run_as_user 'mkdir -p ~/environment'

echo "$(date '+%Y-%m-%d %H:%M:%S') - Configuring VS Code settings..."
setup_user_file "/home/ec2-user/.local/share/code-server/User/settings.json" '{
  "extensions.autoUpdate": false,
  "extensions.autoCheckUpdates": false,
  "security.workspace.trust.enabled": false,
  "workbench.startupEditor": "terminal",
  "task.allowAutomaticTasks": "on",
  "telemetry.telemetryLevel": "off",
  "update.mode": "none",
  "github.copilot.enable": false,
  "github.copilot.chat.enable": false,
  "chat.agent.enabled": false,
  "chat.commandCenter.enabled": false,
  "workbench.settings.showAISearchToggle": false,
  "chat.disableAIFeatures": true,
  "chat.extensionUnification.enabled": false,
  "terminal.integrated.defaultProfile.linux": "zsh",
  "terminal.integrated.showLinkHover": false,
  "terminal.integrated.commandsToSkipShell": [],
  "workbench.sideBar.location": "left",
  "workbench.panel.defaultLocation": "bottom",
  "workbench.auxiliaryBar.visible": false,
  "workbench.secondarySideBar.defaultVisibility": "hidden"
}'

echo "Configuring VS Code keybindings..."
setup_user_file "/home/ec2-user/.local/share/code-server/User/keybindings.json" '[
  {
    "key": "shift+cmd+/",
    "command": "remote.tunnel.forwardCommandPalette"
  }
]'

echo "Setting default workspace..."
# Use shared workspace configuration function
configure_default_workspace "/home/ec2-user/.local/share/code-server/coder.json" "ec2-user"

echo "$(date '+%Y-%m-%d %H:%M:%S') - Installing VS Code extensions..."

# Use shared extension installation function
install_ide_extensions "code-server" "ec2-user"

echo "Restarting code-server..."
systemctl restart code-server@ec2-user

echo "$(date '+%Y-%m-%d %H:%M:%S') - Installing Caddy..."
retry_critical "Caddy repository" "dnf copr enable -y -q @caddy/caddy epel-9-x86_64"
retry_critical "Caddy" "dnf install -y -q caddy"
retry_critical "Caddy service" "systemctl enable --now caddy"

tee /etc/caddy/Caddyfile <<EOF
:80 {
  handle /* {
    reverse_proxy 127.0.0.1:8889
  }
}
EOF

echo "Restarting caddy..."
systemctl restart caddy

echo "$(date '+%Y-%m-%d %H:%M:%S') - VS Code IDE setup completed successfully"