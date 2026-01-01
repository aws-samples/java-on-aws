#!/bin/bash
set -e

CODEEDITOR_CLOUDFRONT_BASE_URL="https://code-editor.amazonaws.com/content/code-editor-server/dist"
CODE_EDITOR_USER="ec2-user"
CODE_EDITOR_PORT="8889"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"
source "${SCRIPT_DIR}/settings.sh"

install_code_editor() {
    log_info "Installing AWS Code Editor..."

    local ARCH=$([ "$(uname -m)" = "aarch64" ] && echo "arm64" || echo "x64")
    log_info "Detected architecture: $ARCH"

    log_info "Downloading AWS Code Editor manifest..."
    MANIFEST_CONTENT=$(curl -L --silent "$CODEEDITOR_CLOUDFRONT_BASE_URL/manifest-latest-linux-$ARCH.json")

    CODE_EDITOR_VERSION=$(echo "$MANIFEST_CONTENT" | jq -r ".codeEditorVersion")
    CODE_EDITOR_DISTRIBUTION_VERSION=$(echo "$MANIFEST_CONTENT" | jq -r ".distributionVersion")
    CODE_EDITOR_CHECKSUM=$(echo "$MANIFEST_CONTENT" | jq -r ".sha256checkSum")

    log_info "Code Editor version: $CODE_EDITOR_VERSION"

    CODE_EDITOR_PKG_NAME="code-editor-$CODE_EDITOR_VERSION-linux-$ARCH"
    CODE_EDITOR_LOCAL_FOLDER="/home/${CODE_EDITOR_USER}/.local/lib/$CODE_EDITOR_PKG_NAME"

    log_info "Downloading AWS Code Editor..."
    retry_critical "AWS Code Editor download" \
        "curl -L '$CODEEDITOR_CLOUDFRONT_BASE_URL/$CODE_EDITOR_VERSION/$CODE_EDITOR_DISTRIBUTION_VERSION' -o /tmp/code-editor-server.tar.gz"

    log_info "Verifying checksum..."
    DOWNLOAD_CHECKSUM=$(sha256sum /tmp/code-editor-server.tar.gz | cut -d ' ' -f 1)
    if [ "$CODE_EDITOR_CHECKSUM" != "$DOWNLOAD_CHECKSUM" ]; then
        echo "💥 FATAL: Checksum mismatch - expected $CODE_EDITOR_CHECKSUM, got $DOWNLOAD_CHECKSUM"
        exit 1
    fi
    echo "✅ Checksum verified"

    log_info "Installing to $CODE_EDITOR_LOCAL_FOLDER..."
    sudo -u $CODE_EDITOR_USER mkdir -p "$CODE_EDITOR_LOCAL_FOLDER"
    sudo -u $CODE_EDITOR_USER mkdir -p "/home/${CODE_EDITOR_USER}/.local/bin"
    sudo -u $CODE_EDITOR_USER tar -xzf /tmp/code-editor-server.tar.gz -C "$CODE_EDITOR_LOCAL_FOLDER"
    sudo -u $CODE_EDITOR_USER ln -sf "$CODE_EDITOR_LOCAL_FOLDER/dist/bin/code-editor-server" \
        "/home/${CODE_EDITOR_USER}/.local/bin/code-editor-server"
    rm /tmp/code-editor-server.tar.gz

    echo "✅ AWS Code Editor installed"
}

configure_code_editor_service() {
    log_info "Configuring Code Editor systemd service..."

    cat > /usr/lib/systemd/system/code-editor@.service << EOF
[Unit]
Description=AWS Code Editor
After=network.target

[Service]
Type=exec
ExecStart=/home/%i/.local/bin/code-editor-server --accept-server-license-terms --host 127.0.0.1 --port ${CODE_EDITOR_PORT} --default-workspace /home/%i/environment
Restart=always
User=%i

[Install]
WantedBy=default.target
EOF

    systemctl daemon-reload
    systemctl enable --now code-editor@${CODE_EDITOR_USER}
    echo "✅ Code Editor service configured"
}

configure_token_auth() {
    log_info "Configuring token authentication..."

    sudo -u $CODE_EDITOR_USER mkdir -p "/home/${CODE_EDITOR_USER}/.code-editor-server/data"
    echo -n "$IDE_PASSWORD" > "/home/${CODE_EDITOR_USER}/.code-editor-server/data/token"
    chown $CODE_EDITOR_USER:$CODE_EDITOR_USER "/home/${CODE_EDITOR_USER}/.code-editor-server/data/token"
    chmod 600 "/home/${CODE_EDITOR_USER}/.code-editor-server/data/token"

    echo "✅ Token authentication configured"
}

configure_code_editor_settings() {
    log_info "Configuring Code Editor settings..."

    local settings_dir="/home/${CODE_EDITOR_USER}/.code-editor-server/data/User"
    sudo -u $CODE_EDITOR_USER mkdir -p "$settings_dir"

    sudo -u $CODE_EDITOR_USER tee "$settings_dir/settings.json" >/dev/null << 'EOF'
{
  "workbench.colorTheme": "Quiet Light",
  "security.workspace.trust.enabled": false,
  "workbench.startupEditor": "terminal",
  "update.mode": "none",
  "telemetry.telemetryLevel": "off",
  "terminal.integrated.defaultProfile.linux": "zsh",
  "redhat.telemetry.enabled": false,
  "java.configuration.checkProjectSettingsExclusions": false,
  "java.help.firstView": "none",
  "java.help.showReleaseNotes": false,
  "java.compile.nullAnalysis.mode": "disabled",
  "java.recommendations.dependency.analytics.show": false
}
EOF

    echo "✅ Code Editor settings configured"
}

install_caddy() {
    log_info "Installing Caddy..."

    retry_critical "Caddy repository" "dnf copr enable -y -q @caddy/caddy epel-9-x86_64"
    retry_critical "Caddy" "dnf install -y -q caddy"
    retry_critical "Caddy service" "systemctl enable --now caddy"

    tee /etc/caddy/Caddyfile <<EOF
:80 {
  handle /* {
    reverse_proxy 127.0.0.1:${CODE_EDITOR_PORT}
  }
}
EOF

    systemctl restart caddy
    echo "✅ Caddy configured"
}

log_info "Starting AWS Code Editor setup..."

sudo -u $CODE_EDITOR_USER mkdir -p /home/${CODE_EDITOR_USER}/environment

install_code_editor
configure_token_auth
configure_code_editor_settings
configure_code_editor_service

log_info "Installing extensions..."
install_ide_extensions "/home/${CODE_EDITOR_USER}/.local/bin/code-editor-server" "$CODE_EDITOR_USER"

configure_default_workspace "/home/${CODE_EDITOR_USER}/.code-editor-server/data/coder.json" "$CODE_EDITOR_USER"

install_caddy

log_info "AWS Code Editor setup completed"
