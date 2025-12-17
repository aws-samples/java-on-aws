#!/bin/bash
set -e

# =============================================================================
# AWS Code Editor Installation Script
# =============================================================================

CODEEDITOR_CLOUDFRONT_BASE_URL="https://code-editor.amazonaws.com/content/code-editor-server/dist"
CODE_EDITOR_USER="ec2-user"
CODE_EDITOR_PORT="8889"

# Source common IDE settings
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

# Helper function for consistent logging
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}


# =============================================================================
# Installation Functions
# =============================================================================

install_code_editor() {
    log_info "Installing AWS Code Editor..."

    # Architecture detection (arm64 or x64 for Code Editor)
    local ARCH=$([ "$(uname -m)" = "aarch64" ] && echo "arm64" || echo "x64")
    log_info "Detected architecture: $ARCH"

    # Download manifest
    log_info "Downloading AWS Code Editor manifest..."
    MANIFEST_CONTENT=$(curl -L --silent "$CODEEDITOR_CLOUDFRONT_BASE_URL/manifest-latest-linux-$ARCH.json")

    CODE_EDITOR_VERSION=$(echo "$MANIFEST_CONTENT" | jq -r ".codeEditorVersion")
    CODE_EDITOR_DISTRIBUTION_VERSION=$(echo "$MANIFEST_CONTENT" | jq -r ".distributionVersion")
    CODE_EDITOR_CHECKSUM=$(echo "$MANIFEST_CONTENT" | jq -r ".sha256checkSum")

    log_info "Code Editor version: $CODE_EDITOR_VERSION"

    CODE_EDITOR_PKG_NAME="code-editor-$CODE_EDITOR_VERSION-linux-$ARCH"
    CODE_EDITOR_LOCAL_FOLDER="/home/${CODE_EDITOR_USER}/.local/lib/$CODE_EDITOR_PKG_NAME"

    # Download Code Editor
    log_info "Downloading AWS Code Editor..."
    retry_critical "AWS Code Editor download" \
        "curl -L '$CODEEDITOR_CLOUDFRONT_BASE_URL/$CODE_EDITOR_VERSION/$CODE_EDITOR_DISTRIBUTION_VERSION' -o /tmp/code-editor-server.tar.gz"

    # Verify checksum
    log_info "Verifying checksum..."
    DOWNLOAD_CHECKSUM=$(sha256sum /tmp/code-editor-server.tar.gz | cut -d ' ' -f 1)
    if [ "$CODE_EDITOR_CHECKSUM" != "$DOWNLOAD_CHECKSUM" ]; then
        echo "💥 FATAL: Checksum mismatch - expected $CODE_EDITOR_CHECKSUM, got $DOWNLOAD_CHECKSUM"
        exit 1
    fi
    echo "✅ Checksum verified"

    # Install to user's .local directory
    log_info "Installing to $CODE_EDITOR_LOCAL_FOLDER..."
    sudo -u $CODE_EDITOR_USER mkdir -p "$CODE_EDITOR_LOCAL_FOLDER"
    sudo -u $CODE_EDITOR_USER mkdir -p "/home/${CODE_EDITOR_USER}/.local/bin"
    sudo -u $CODE_EDITOR_USER tar -xzf /tmp/code-editor-server.tar.gz -C "$CODE_EDITOR_LOCAL_FOLDER"
    sudo -u $CODE_EDITOR_USER ln -sf "$CODE_EDITOR_LOCAL_FOLDER/dist/bin/code-editor-server" \
        "/home/${CODE_EDITOR_USER}/.local/bin/code-editor-server"
    rm /tmp/code-editor-server.tar.gz

    echo "✅ AWS Code Editor installed successfully"
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

# =============================================================================
# Main Installation
# =============================================================================

log_info "Starting AWS Code Editor setup..."

# Create environment folder
sudo -u $CODE_EDITOR_USER mkdir -p /home/${CODE_EDITOR_USER}/environment

# Install Code Editor
install_code_editor

# Configure token authentication
configure_token_auth

# Configure systemd service
configure_code_editor_service

# Install extensions using shared function
log_info "Installing extensions..."
install_ide_extensions "/home/${CODE_EDITOR_USER}/.local/bin/code-editor-server" "$CODE_EDITOR_USER"

# Configure default workspace using shared function
configure_default_workspace "/home/${CODE_EDITOR_USER}/.code-editor-server/data/coder.json" "$CODE_EDITOR_USER"

# Install and configure Caddy
install_caddy

log_info "AWS Code Editor setup completed successfully"
