#!/bin/bash
set -e

VSCODE_VERSION="4.106.3"
VSCODE_USER="ec2-user"
VSCODE_PORT="8889"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"
source "${SCRIPT_DIR}/settings.sh"

install_code_server() {
    log_info "Installing code-server ${VSCODE_VERSION}..."

    codeServer=$(dnf list installed code-server 2>/dev/null | wc -l)
    if [ "$codeServer" -eq "0" ]; then
        retry_critical "VS Code Server ${VSCODE_VERSION}" \
            "sudo -u $VSCODE_USER bash -c 'curl -fsSL https://code-server.dev/install.sh | sh -s -- --version $VSCODE_VERSION'"
        retry_critical "VS Code Server service" "systemctl enable --now code-server@${VSCODE_USER}"
    fi
}

configure_code_server() {
    log_info "Configuring code-server..."

    sudo -u $VSCODE_USER mkdir -p "/home/${VSCODE_USER}/.config/code-server"
    sudo -u $VSCODE_USER tee "/home/${VSCODE_USER}/.config/code-server/config.yaml" >/dev/null <<EOF
cert: false
auth: password
password: "$IDE_PASSWORD"
bind-addr: 127.0.0.1:${VSCODE_PORT}
EOF
}

configure_vscode_settings() {
    log_info "Configuring VS Code settings..."

    local settings_dir="/home/${VSCODE_USER}/.local/share/code-server/User"
    sudo -u $VSCODE_USER mkdir -p "$settings_dir"

    sudo -u $VSCODE_USER tee "$settings_dir/settings.json" >/dev/null << 'EOF'
{
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
}
EOF

    sudo -u $VSCODE_USER tee "$settings_dir/keybindings.json" >/dev/null << 'EOF'
[
  {
    "key": "shift+cmd+/",
    "command": "remote.tunnel.forwardCommandPalette"
  }
]
EOF
}

install_caddy() {
    log_info "Installing Caddy..."

    retry_critical "Caddy repository" "dnf copr enable -y -q @caddy/caddy epel-9-x86_64"
    retry_critical "Caddy" "dnf install -y -q caddy"
    retry_critical "Caddy service" "systemctl enable --now caddy"

    tee /etc/caddy/Caddyfile <<EOF
:80 {
  handle /* {
    reverse_proxy 127.0.0.1:${VSCODE_PORT}
  }
}
EOF

    systemctl restart caddy
    echo "✅ Caddy configured"
}

log_info "Starting VS Code Server setup..."

sudo -u $VSCODE_USER mkdir -p /home/${VSCODE_USER}/environment

install_code_server
configure_code_server
configure_vscode_settings

log_info "Installing extensions..."
install_ide_extensions "code-server" "$VSCODE_USER"

configure_default_workspace "/home/${VSCODE_USER}/.local/share/code-server/coder.json" "$VSCODE_USER"

systemctl restart code-server@${VSCODE_USER}

install_caddy

log_info "VS Code Server setup completed"
