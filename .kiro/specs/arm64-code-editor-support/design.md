# Design Document: ARM64 and Code Editor Support

## Overview

This design adds ARM64 (Graviton) architecture support to the workshop IDE infrastructure and introduces AWS Code Editor as an alternative to code-server. The architecture is controlled by a single CDK parameter that drives instance type selection and script behavior.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CDK Ide Construct                        │
│  ┌─────────────────┐                                            │
│  │ Architecture    │──► ARM64 ──► m7g, m6g, t4g instances       │
│  │ Parameter       │──► X86_64 ──► m7i-flex, m6i, m5 instances  │
│  └────────┬────────┘                                            │
│           │                                                      │
│           ▼                                                      │
│  ┌─────────────────┐     ┌─────────────────┐                    │
│  │ UserData        │────►│ ARCH env var    │                    │
│  └─────────────────┘     └────────┬────────┘                    │
└───────────────────────────────────┼─────────────────────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Bootstrap Scripts                           │
│  ┌─────────────────┐     ┌─────────────────┐                    │
│  │ bootstrap.sh    │────►│ base.sh         │ (arch-aware)       │
│  └────────┬────────┘     └─────────────────┘                    │
│           │                                                      │
│           ├──► vscode.sh (code-server, port 8889)               │
│           │    OR                                                │
│           └──► code-editor.sh (AWS Code Editor, port 8889)      │
│                                                                  │
│  (each IDE script is self-contained with extensions)            │
└─────────────────────────────────────────────────────────────────┘
```

## Components and Interfaces

### 1. CDK Ide Construct Changes

**File:** `java-on-aws/infra/cdk/src/main/java/sample/com/constructs/Ide.java`

These are **IdeProps properties** (set at CDK synthesis time via builder pattern), not CloudFormation parameters:

```java
public enum IdeArch {
    ARM64,
    X86_64
}

public enum IdeType {
    CODE_EDITOR,  // AWS Code Editor (default)
    VSCODE        // code-server
}

public static class IdeProps {
    // New fields - set via builder pattern
    private IdeArch ideArch = IdeArch.ARM64;
    private IdeType ideType = IdeType.CODE_EDITOR;

    // Derived instance types based on architecture
    private static final List<String> ARM64_INSTANCE_TYPES =
        Arrays.asList("m7g.xlarge", "m6g.xlarge", "c7g.xlarge", "t4g.xlarge");
    private static final List<String> X86_64_INSTANCE_TYPES =
        Arrays.asList("m7i-flex.xlarge", "m7a.xlarge", "m6i.xlarge", "m6a.xlarge", "m5.xlarge", "t3.xlarge");

    public List<String> getInstanceTypes() {
        return ideArch == IdeArch.ARM64 ? ARM64_INSTANCE_TYPES : X86_64_INSTANCE_TYPES;
    }

    public IMachineImage getMachineImage() {
        return ideArch == IdeArch.ARM64
            ? MachineImage.latestAmazonLinux2023(AmazonLinux2023ImageSsmParameterProps.builder()
                .cpuType(AmazonLinuxCpuType.ARM_64).build())
            : MachineImage.latestAmazonLinux2023();
    }

    public IdeArch getIdeArch() { return ideArch; }
    public IdeType getIdeType() { return ideType; }
}

// Builder additions
public Builder ideArch(IdeArch ideArch) { props.ideArch = ideArch; return this; }
public Builder ideType(IdeType ideType) { props.ideType = ideType; return this; }
```

**Usage example:**
```java
new Ide(this, "Ide", IdeProps.builder()
    .vpc(vpc)
    .ideArch(IdeArch.ARM64)      // default
    .ideType(IdeType.CODE_EDITOR) // default
    .build());
```

### 2. UserData Template Changes

**File:** `java-on-aws/infra/cdk/src/main/resources/userdata.sh`

Add architecture and IDE type exports:
```bash
export ARCH="${ARCH}"          # ARM64 or X86_64
export IDE_TYPE="${IDE_TYPE}"  # code-editor or vscode
```

The CDK construct passes these values via string substitution in userdata.sh.

### 3. Architecture Detection in Scripts

**File:** `java-on-aws/infra/scripts/ide/base.sh`

```bash
# Architecture detection - use CDK-provided value or detect from system
if [ -z "$ARCH" ]; then
    ARCH=$(uname -m)
fi

# Normalize architecture names for different tools
case $ARCH in
    aarch64|ARM64|arm64)
        ARCH_UNAME="aarch64"
        ARCH_K8S="arm64"
        ARCH_SAM="arm64"
        ARCH_GENERIC="arm64"
        ARCH_YQ="arm64"
        ;;
    *)
        ARCH_UNAME="x86_64"
        ARCH_K8S="amd64"
        ARCH_SAM="x86_64"
        ARCH_GENERIC="x86_64"
        ARCH_YQ="amd64"
        ;;
esac
```

### 4. AWS Code Editor Script

**File:** `java-on-aws/infra/scripts/ide/code-editor.sh` (NEW)

```bash
#!/bin/bash
set -e

CODEEDITOR_CLOUDFRONT_BASE_URL="https://code-editor.amazonaws.com/content/code-editor-server/dist"
CODE_EDITOR_USER="${CODE_EDITOR_USER:-ec2-user}"
CODE_EDITOR_PORT="8889"

# Architecture detection
ARCH=$([ "$(uname -m)" = "aarch64" ] && echo "arm64" || echo "x64")

install_code_editor() {
    log_info "Downloading AWS Code Editor manifest..."
    MANIFEST_CONTENT=$(curl -L --silent "$CODEEDITOR_CLOUDFRONT_BASE_URL/manifest-latest-linux-$ARCH.json")

    CODE_EDITOR_VERSION=$(echo "$MANIFEST_CONTENT" | jq -r ".codeEditorVersion")
    CODE_EDITOR_DISTRIBUTION_VERSION=$(echo "$MANIFEST_CONTENT" | jq -r ".distributionVersion")
    CODE_EDITOR_CHECKSUM=$(echo "$MANIFEST_CONTENT" | jq -r ".sha256checkSum")

    CODE_EDITOR_PKG_NAME="code-editor-$CODE_EDITOR_VERSION-linux-$ARCH"
    CODE_EDITOR_LOCAL_FOLDER="/home/${CODE_EDITOR_USER}/.local/lib/$CODE_EDITOR_PKG_NAME"

    # Download and verify checksum
    retry_critical "AWS Code Editor download" \
        "curl -L '$CODEEDITOR_CLOUDFRONT_BASE_URL/$CODE_EDITOR_VERSION/$CODE_EDITOR_DISTRIBUTION_VERSION' \
         -o /tmp/code-editor-server.tar.gz"

    DOWNLOAD_CHECKSUM=$(sha256sum /tmp/code-editor-server.tar.gz | cut -d ' ' -f 1)
    if [ "$CODE_EDITOR_CHECKSUM" != "$DOWNLOAD_CHECKSUM" ]; then
        echo "💥 FATAL: Checksum mismatch - expected $CODE_EDITOR_CHECKSUM, got $DOWNLOAD_CHECKSUM"
        exit 1
    fi

    # Install
    sudo -u $CODE_EDITOR_USER mkdir -p "$CODE_EDITOR_LOCAL_FOLDER"
    sudo -u $CODE_EDITOR_USER mkdir -p "/home/${CODE_EDITOR_USER}/.local/bin"
    sudo -u $CODE_EDITOR_USER tar -xzf /tmp/code-editor-server.tar.gz -C "$CODE_EDITOR_LOCAL_FOLDER"
    sudo -u $CODE_EDITOR_USER ln -sf "$CODE_EDITOR_LOCAL_FOLDER/dist/bin/code-editor-server" \
        "/home/${CODE_EDITOR_USER}/.local/bin/code-editor-server"
    rm /tmp/code-editor-server.tar.gz
}

configure_code_editor_service() {
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

    systemctl enable --now code-editor@${CODE_EDITOR_USER}
}

configure_token_auth() {
    sudo -u $CODE_EDITOR_USER mkdir -p "/home/${CODE_EDITOR_USER}/.code-editor-server/data"
    echo -n "$IDE_PASSWORD" > "/home/${CODE_EDITOR_USER}/.code-editor-server/data/token"
    chown $CODE_EDITOR_USER:$CODE_EDITOR_USER "/home/${CODE_EDITOR_USER}/.code-editor-server/data/token"
}
```

### 5. ide-settings.sh (NEW)

**File:** `java-on-aws/infra/scripts/ide/ide-settings.sh` (NEW)

Common settings shared by both IDEs:

```bash
#!/bin/bash
# Common IDE settings - sourced by vscode.sh and code-editor.sh

# Extensions to install
EXTENSIONS="vscjava.vscode-java-pack,ms-azuretools.vscode-docker,ms-kubernetes-tools.vscode-kubernetes-tools"

# Extensions to uninstall (pre-installed but unwanted)
EXTENSIONS_UNINSTALL="AmazonWebServices.aws-toolkit-vscode,AmazonWebServices.amazon-q-vscode"

# Default workspace folder
DEFAULT_WORKSPACE="/home/ec2-user/environment"

# Uninstall extensions using provided binary
# Usage: uninstall_ide_extensions <binary_command> <user>
uninstall_ide_extensions() {
    local binary_cmd="$1"
    local user="$2"

    IFS=',' read -ra extension_array <<< "$EXTENSIONS_UNINSTALL"
    for extension in "${extension_array[@]}"; do
        extension=$(echo "$extension" | xargs)
        if [ -n "$extension" ]; then
            echo "Uninstalling extension: $extension"
            sudo -u $user $binary_cmd --uninstall-extension $extension 2>/dev/null || true
        fi
    done
}

# Install extensions using provided binary
# Usage: install_ide_extensions <binary_command> <user>
install_ide_extensions() {
    local binary_cmd="$1"
    local user="$2"

    # First uninstall unwanted extensions
    uninstall_ide_extensions "$binary_cmd" "$user"

    IFS=',' read -ra extension_array <<< "$EXTENSIONS"
    for extension in "${extension_array[@]}"; do
        extension=$(echo "$extension" | xargs)
        if [ -n "$extension" ]; then
            echo "Installing extension: $extension"
            retry_optional "Extension $extension" \
                "sudo -u $user $binary_cmd --install-extension $extension --force"
        fi
    done
}

# Configure default workspace
# Usage: configure_default_workspace <coder_json_path> <user>
configure_default_workspace() {
    local coder_json_path="$1"
    local user="$2"

    if [ ! -f "$coder_json_path" ]; then
        sudo -u $user mkdir -p "$(dirname "$coder_json_path")"
        echo "{ \"query\": { \"folder\": \"$DEFAULT_WORKSPACE\" } }" | sudo -u $user tee "$coder_json_path" >/dev/null
    fi
}
```

### 6. vscode.sh Updates

**File:** `java-on-aws/infra/scripts/ide/vscode.sh` (MODIFY)

Changes:
1. Remove inline EXTENSIONS - source from ide-settings.sh
2. Use shared `install_ide_extensions` function
3. Use shared `configure_default_workspace` function
4. Keep all code-server specific settings (Copilot suppression, keybindings, etc.)

```bash
# Source common settings
source "$(dirname "$0")/ide-settings.sh"

# ... existing code-server installation ...

# Use shared extension installation
install_ide_extensions "code-server" "ec2-user"

# Use shared workspace config
configure_default_workspace "/home/ec2-user/.local/share/code-server/coder.json" "ec2-user"
```

### 7. code-editor.sh (NEW)

**File:** `java-on-aws/infra/scripts/ide/code-editor.sh` (NEW)

Setup includes:
- Installation with checksum verification
- Token auth
- Settings.json (workspace trust disabled, terminal on startup, telemetry off, AWS Toolkit/Q popups suppressed)
- Extensions (via shared function)
- Default workspace folder (via shared function - coder.json)
- Caddy proxy
- Systemd service

**Note:** Two separate configs control the startup experience:
1. **coder.json** - sets which folder opens in the file explorer (`~/environment`)
2. **settings.json** - sets what opens in the editor area (`"workbench.startupEditor": "terminal"`)

```bash
#!/bin/bash
set -e

source "$(dirname "$0")/ide-settings.sh"

CODE_EDITOR_USER="ec2-user"
CODE_EDITOR_PORT="8889"

# ... installation code ...

# Token auth
sudo -u $CODE_EDITOR_USER mkdir -p "/home/${CODE_EDITOR_USER}/.code-editor-server/data"
echo -n "$IDE_PASSWORD" > "/home/${CODE_EDITOR_USER}/.code-editor-server/data/token"

# Settings.json - disable trust dialog, open terminal on startup, suppress popups
sudo -u $CODE_EDITOR_USER tee "$settings_dir/settings.json" << 'EOF'
{
  "security.workspace.trust.enabled": false,
  "workbench.startupEditor": "terminal",
  "telemetry.telemetryLevel": "off",
  "aws.telemetry": false,
  "aws.suppressPrompts": { ... },
  "amazonQ.showWalkthrough": false
}
EOF

# Extensions
install_ide_extensions "/home/${CODE_EDITOR_USER}/.local/bin/code-editor-server" "$CODE_EDITOR_USER"

# Default workspace folder (coder.json)
configure_default_workspace "/home/${CODE_EDITOR_USER}/.code-editor-server/data/coder.json" "$CODE_EDITOR_USER"

# Caddy (same as vscode.sh)
# Systemd service
```

### 8. bootstrap.sh Updates

**File:** `java-on-aws/infra/scripts/ide/bootstrap.sh` (MODIFY)

Read IDE_TYPE from environment (set by CDK via UserData):

```bash
# IDE type - from CDK parameter via UserData, default to code-editor
IDE_TYPE="${IDE_TYPE:-code-editor}"

# Set alias based on IDE type
if [ "$IDE_TYPE" = "code-editor" ]; then
    echo 'alias code="/home/ec2-user/.local/bin/code-editor-server"' >> /etc/profile.d/workshop.sh
else
    echo 'alias code="code-server"' >> /etc/profile.d/workshop.sh
fi

# Run selected IDE setup
bash infra/scripts/ide/${IDE_TYPE}.sh
```

### 9. shell.sh Updates

**File:** `java-on-aws/infra/scripts/ide/shell.sh` (MODIFY)

1. Dynamic code alias in .zshrc
2. Check both settings.json locations for zsh terminal config

```bash
# In .zshrc - dynamic alias
if [ -x "/home/ec2-user/.local/bin/code-editor-server" ]; then
    alias code="/home/ec2-user/.local/bin/code-editor-server"
elif command -v code-server &>/dev/null; then
    alias code=/usr/lib/code-server/bin/code-server
fi

# Update settings.json for zsh - check both locations
for settings_path in \
    "/home/ec2-user/.local/share/code-server/User/settings.json" \
    "/home/ec2-user/.code-editor-server/data/User/settings.json"; do
    if [ -f "$settings_path" ]; then
        jq '. + {"terminal.integrated.defaultProfile.linux": "zsh"}' "$settings_path" > /tmp/settings.json \
            && mv /tmp/settings.json "$settings_path"
        break
    fi
done
```

### 10. CDK URL Output (Conditional based on IdeType)

**File:** `java-on-aws/infra/cdk/src/main/java/sample/com/constructs/Ide.java` (MODIFY)

The URL output format differs based on IDE type:
- **CODE_EDITOR**: Token-based URL for seamless Workshop Studio access
- **VSCODE**: Standard URL (password entered separately)

```java
// Build URL based on IDE type
String ideUrl;
if (props.getIdeType() == IdeType.CODE_EDITOR) {
    // Token-based URL for Code Editor
    ideUrl = "https://" + distribution.getDistributionDomainName() +
             "/?folder=/home/ec2-user/environment&tkn=" + getIdePassword(instanceName);
} else {
    // Standard URL for code-server (password entered via login page)
    ideUrl = "https://" + distribution.getDistributionDomainName();
}

var ideUrlOutput = CfnOutput.Builder.create(this, "Url")
    .value(ideUrl)
    .description("Workshop IDE Url")
    .exportName(instanceName + "-url")
    .build();
```

### 11. Kiro CLI Installation

**File:** `java-on-aws/infra/scripts/ide/base.sh` (addition)

```bash
install_kiro_cli() {
    log_info "Installing Kiro CLI..."
    retry_optional "Kiro CLI" \
        "sudo -u ec2-user curl -fsSL https://cli.kiro.dev/install -o /tmp/kiro_cli_install.sh && \
         sudo -u ec2-user bash /tmp/kiro_cli_install.sh"

    # Verify installation
    if sudo -u ec2-user kiro-cli --version >/dev/null 2>&1; then
        echo "✅ Success: Kiro CLI $(sudo -u ec2-user kiro-cli --version)"
    else
        echo "⚠️  Warning: Kiro CLI installation could not be verified"
    fi
}
```

## Data Models

### IdeArch Enum (CDK)

```java
public enum IdeArch {
    ARM64("arm64", "aarch64"),
    X86_64("x86_64", "x86_64");

    private final String awsValue;
    private final String unameValue;

    IdeArch(String awsValue, String unameValue) {
        this.awsValue = awsValue;
        this.unameValue = unameValue;
    }

    public String getAwsValue() { return awsValue; }
    public String getUnameValue() { return unameValue; }
}
```

### IdeType Enum (CDK)

```java
public enum IdeType {
    CODE_EDITOR("code-editor"),
    VSCODE("vscode");

    private final String scriptName;

    IdeType(String scriptName) {
        this.scriptName = scriptName;
    }

    public String getScriptName() { return scriptName; }
}
```

### Instance Type Mapping

| Architecture | Instance Types (priority order) |
|--------------|--------------------------------|
| ARM64 | m7g.xlarge, m6g.xlarge, c7g.xlarge, t4g.xlarge |
| X86_64 | m7i-flex.xlarge, m7a.xlarge, m6i.xlarge, m6a.xlarge, m5.xlarge, t3.xlarge |

### Download URL Patterns

| Tool | ARM64 URL Pattern | X86_64 URL Pattern |
|------|-------------------|-------------------|
| kubectl | `.../arm64/kubectl` | `.../amd64/kubectl` |
| SAM CLI | `...-arm64.zip` | `...-x86_64.zip` |
| eks-node-viewer | `..._Linux_arm64` | `..._Linux_x86_64` |
| SOCI | `...-linux-arm64.tar.gz` | `...-linux-amd64.tar.gz` |
| yq | `yq_linux_arm64.tar.gz` | `yq_linux_amd64.tar.gz` |

## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system-essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

### Property 1: Architecture determines instance types
*For any* architecture value (ARM64 or X86_64), the returned instance type list SHALL contain only instances of the matching architecture family (g-suffix for ARM64, no g-suffix for X86_64).
**Validates: Requirements 1.2, 1.3, 7.1, 7.2**

### Property 2: Architecture propagates to UserData
*For any* architecture parameter value, the rendered UserData SHALL contain an export statement setting ARCH to the corresponding value.
**Validates: Requirements 1.4**

### Property 3: Download URLs match architecture
*For any* tool download and architecture combination, the generated URL SHALL contain the architecture-appropriate path segment (arm64/aarch64 for ARM64, amd64/x86_64 for X86_64).
**Validates: Requirements 2.2, 2.3, 2.4, 2.5, 2.6, 2.7**

### Property 4: Checksum verification rejects mismatches
*For any* downloaded file, if the computed SHA256 checksum does not match the expected checksum, the installation SHALL fail with an error.
**Validates: Requirements 3.2**

### Property 5: Extension installation succeeds for each IDE
*For any* IDE (code-server or code-editor-server), the extension installation loop SHALL invoke the correct binary with --install-extension flag and handle failures gracefully.
**Validates: Requirements 4.1-4.7**

## Error Handling

| Error Scenario | Handling Strategy |
|----------------|-------------------|
| Instance type unavailable | Try next type in architecture-specific list |
| Download fails | Retry up to 5 times with 5s delay |
| Checksum mismatch | Fail immediately with clear error message |
| Extension install fails | Log warning, continue with remaining extensions |
| Kiro CLI install fails | Log warning, continue bootstrap |

## Testing Strategy

### Unit Tests
- CDK construct tests for architecture parameter handling
- Instance type list selection based on architecture
- UserData rendering with architecture variable

### Property-Based Tests
Using JUnit 5 with jqwik for property-based testing:

1. **Architecture → Instance Types mapping**: Generate random architecture values, verify instance types match
2. **URL generation**: Generate architecture values, verify URLs contain correct path segments
3. **Checksum verification**: Generate random file contents and checksums, verify mismatch detection

### Integration Tests
- Deploy stack with ARM64 architecture, verify Graviton instance launches
- Deploy stack with X86_64 architecture, verify Intel instance launches
- Verify code-editor.sh installs and starts AWS Code Editor
- Verify extensions install successfully on both IDEs

## File Changes Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `Ide.java` | Modify | Add Architecture enum, IdeType enum, conditional URL output |
| `userdata.sh` | Modify | Add ARCH and IDE_TYPE exports |
| `base.sh` | Modify | Add arch detection, update download URLs, add Kiro CLI |
| `ide-settings.sh` | New | Common extensions list and workspace config |
| `code-editor.sh` | New | AWS Code Editor setup (minimal, uses defaults) |
| `vscode.sh` | Modify | Source ide-settings.sh, use shared functions |
| `bootstrap.sh` | Modify | Read IDE_TYPE from env (default: code-editor), dynamic alias |
| `shell.sh` | Modify | Dynamic code alias, check both settings.json locations |
