#!/bin/bash
set -e

# =============================================================================
# VERSION DEFINITIONS (managed by Renovate)
# =============================================================================

# VS Code Server version
VSCODE_VERSION="4.106.3"

# VS Code Extensions
EXTENSIONS="shardulm94.trailing-spaces,ms-kubernetes-tools.vscode-kubernetes-tools,ms-azuretools.vscode-docker"

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
  retry_critical "VS Code Server" "sudo -u ec2-user bash -c 'curl -fsSL https://code-server.dev/install.sh | sh -s -- --version $VSCODE_VERSION'"
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
  "update.mode": "none"
}'

echo "Configuring VS Code keybindings..."
setup_user_file "/home/ec2-user/.local/share/code-server/User/keybindings.json" '[
  {
    "key": "shift+cmd+/",
    "command": "remote.tunnel.forwardCommandPalette"
  }
]'

echo "Setting default workspace..."
if [ ! -f "/home/ec2-user/.local/share/code-server/coder.json" ]; then
  setup_user_file "/home/ec2-user/.local/share/code-server/coder.json" '{ "query": { "folder": "/home/ec2-user/environment" } }'
fi

echo "$(date '+%Y-%m-%d %H:%M:%S') - Installing VS Code extensions..."

if [ ! -z "$EXTENSIONS" ]; then
    IFS=',' read -ra extension_array <<< "$EXTENSIONS"

    # Install extensions with retry logic (5×5s LOG mode - continue on failure)
    for extension in "${extension_array[@]}"; do
        # Trim whitespace
        extension=$(echo "$extension" | xargs)
        if [ ! -z "$extension" ]; then
            echo "Installing extension: $extension"
            retry_optional "VS Code extension $extension" "run_as_user 'code-server --install-extension $extension --force'"
        fi
    done
else
    echo "No VS Code extensions specified, skipping extension installation"
fi

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