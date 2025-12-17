#!/bin/bash
# =============================================================================
# Common IDE settings - sourced by vscode.sh and code-editor.sh
# =============================================================================

# Extensions
EXTENSIONS="vscjava.vscode-java-pack,ms-azuretools.vscode-docker,ms-kubernetes-tools.vscode-kubernetes-tools"
# EXTENSIONS="AmazonWebServices.aws-toolkit-vscode,vscjava.vscode-java-pack,ms-azuretools.vscode-docker,ms-kubernetes-tools.vscode-kubernetes-tools,esbenp.prettier-vscode,shardulm94.trailing-spaces"

# Default workspace folder
DEFAULT_WORKSPACE="/home/ec2-user/environment"

# =============================================================================
# Shared Functions
# =============================================================================

# Install extensions using provided binary
# Usage: install_ide_extensions <binary_command> <user>
install_ide_extensions() {
    local binary_cmd="$1"
    local user="$2"

    echo "Installing IDE extensions using: $binary_cmd"

    IFS=',' read -ra extension_array <<< "$EXTENSIONS"
    for extension in "${extension_array[@]}"; do
        extension=$(echo "$extension" | xargs)
        if [ -n "$extension" ]; then
            echo "Installing extension: $extension"
            if command -v retry_optional >/dev/null 2>&1; then
                retry_optional "Extension $extension" \
                    "sudo -u $user $binary_cmd --install-extension $extension --force"
            else
                if sudo -u $user $binary_cmd --install-extension $extension --force 2>/dev/null; then
                    echo "✅ Success: Extension $extension"
                else
                    echo "⚠️  Warning: Extension $extension failed (continuing)"
                fi
            fi
        fi
    done
}

# Configure default workspace
# Usage: configure_default_workspace <coder_json_path> <user>
configure_default_workspace() {
    local coder_json_path="$1"
    local user="$2"

    if [ ! -f "$coder_json_path" ]; then
        echo "Configuring default workspace: $DEFAULT_WORKSPACE"
        sudo -u $user mkdir -p "$(dirname "$coder_json_path")"
        echo "{ \"query\": { \"folder\": \"$DEFAULT_WORKSPACE\" } }" | sudo -u $user tee "$coder_json_path" >/dev/null
    fi
}
