#!/bin/bash
set -e

# =============================================================================
# VERSION DEFINITIONS (managed by Renovate)
# =============================================================================

# Default Java version
JAVA_VERSION="25"

# Development tools
NVM_VERSION="0.40.3"
NODE_VERSION="20"
MAVEN_VERSION="3.9.11"

# Kubernetes tools
KUBECTL_VERSION="1.34.2"
HELM_VERSION="3.19.3"
EKS_NODE_VIEWER_VERSION="0.7.4"

# Container tools
SOCI_VERSION="0.12.0"

# Utilities
YQ_VERSION="4.49.2"

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

# Helper function for consistent logging
log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Helper function for error handling
handle_error() {
    echo "ERROR: $1" >&2
    exit 1
}

# Helper function for download verification with retry
download_and_verify() {
    local url="$1"
    local output="$2"
    local description="$3"

    log_info "Downloading $description..."
    retry_critical "$description" "wget -q '$url' -O '$output'"
}

cd /tmp

# Temporarily disable the libuv use of io_uring
export UV_USE_IO_URING=0

# Development Languages & Runtimes
install_java() {
    log_info "Installing Java versions 8, 17, 21, 25 and setting ${JAVA_VERSION} as default..."

    # Install all Java versions
    retry_critical "Java versions (8,17,21,25)" "sudo dnf install -y -q java-1.8.0-amazon-corretto-devel java-17-amazon-corretto-devel java-21-amazon-corretto-devel java-25-amazon-corretto-devel >/dev/null"

    # Set default Java version
    sudo update-alternatives --set java /usr/lib/jvm/java-${JAVA_VERSION}-amazon-corretto.x86_64/bin/java
    sudo update-alternatives --set javac /usr/lib/jvm/java-${JAVA_VERSION}-amazon-corretto.x86_64/bin/javac

    # Set JAVA_HOME
    JAVA_HOME=/usr/lib/jvm/java-${JAVA_VERSION}-amazon-corretto.x86_64
    echo "export JAVA_HOME=${JAVA_HOME}" | sudo tee -a /etc/profile.d/workshop.sh >/dev/null

    # Verify installation
    java -version
}

install_java

install_nodejs() {
    log_info "Installing Node.js ${NODE_VERSION} and tools..."

    # Install NVM
    retry_critical "NVM ${NVM_VERSION}" "curl -sS -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash"

    # Setup NVM environment
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    # Install Node.js and tools
    retry_critical "Node.js ${NODE_VERSION}" "nvm install ${NODE_VERSION}"

    # Install npm and get version
    install_with_version "npm" "nvm install-latest-npm" "npm --version"

    # Install CDK and Artillery separately to get individual versions
    install_with_version "CDK" "npm install -g aws-cdk" "cdk version"
    install_with_version "Artillery" "npm install -g artillery" "artillery -v | head -1"
}

install_nodejs

# Build Tools
install_maven() {
    log_info "Installing Maven ${MAVEN_VERSION}..."

    local mvn_foldername=apache-maven-${MAVEN_VERSION}
    local mvn_filename=apache-maven-${MAVEN_VERSION}-bin.tar.gz
    local mvn_url="https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/${mvn_filename}"

    retry_critical "Maven ${MAVEN_VERSION}" "curl -sS -4 -L '$mvn_url' | tar -xz"

    sudo mv "$mvn_foldername" /usr/lib/maven
    echo "export M2_HOME=/usr/lib/maven" | sudo tee -a /etc/profile.d/workshop.sh >/dev/null
    echo "export PATH=\${PATH}:\${M2_HOME}/bin" | sudo tee -a /etc/profile.d/workshop.sh >/dev/null
    sudo ln -s /usr/lib/maven/bin/mvn /usr/local/bin
}

install_maven

# AWS Tools
install_aws_tools() {
    log_info "Installing AWS SAM CLI..."
    curl -sS -L "https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-x86_64.zip" -o "aws-sam-cli-linux-x86_64.zip"

    unzip -q aws-sam-cli-linux-x86_64.zip -d sam-installation
    install_with_version "AWS SAM CLI" "sudo ./sam-installation/install --update" "/usr/local/bin/sam --version | awk '{print \$4}'"
    rm -rf ./sam-installation/ aws-sam-cli-linux-x86_64.zip

    log_info "Installing Session Manager Plugin..."
    curl -sS -L "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
    install_with_version "Session Manager Plugin" "sudo dnf -q install -y session-manager-plugin.rpm" "session-manager-plugin --version 2>/dev/null | head -1"
    rm session-manager-plugin.rpm
}

install_aws_tools

install_kubernetes_tools() {
    log_info "Installing kubectl ${KUBECTL_VERSION}..."
    download_and_verify "https://s3.us-west-2.amazonaws.com/amazon-eks/${KUBECTL_VERSION}/2025-11-13/bin/linux/amd64/kubectl" "kubectl" "kubectl ${KUBECTL_VERSION}"

    chmod +x ./kubectl
    mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
    echo "export PATH=\$PATH:\$HOME/bin" | sudo tee -a /etc/profile.d/workshop.sh >/dev/null
    kubectl completion bash >> ~/.bash_completion
    echo "alias k=kubectl" | sudo tee -a /etc/profile.d/workshop.sh >/dev/null
    echo "complete -F __start_kubectl k" >> ~/.bashrc

    log_info "Installing Helm ${HELM_VERSION}..."
    retry_critical "Helm ${HELM_VERSION}" "curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 get_helm.sh && ./get_helm.sh --version v${HELM_VERSION}"
    helm completion bash >> ~/.bash_completion

    log_info "Installing eks-node-viewer ${EKS_NODE_VIEWER_VERSION}..."
    download_and_verify "https://github.com/awslabs/eks-node-viewer/releases/download/v${EKS_NODE_VIEWER_VERSION}/eks-node-viewer_Linux_x86_64" "eks-node-viewer" "eks-node-viewer ${EKS_NODE_VIEWER_VERSION}"
    chmod +x eks-node-viewer
    sudo mv eks-node-viewer /usr/local/bin

    log_info "Installing k9s..."
    export PATH="$HOME/.local/bin:$PATH"  # k9s installs to ~/.local/bin
    install_with_version "k9s" "curl -sS https://webinstall.dev/k9s | bash" "k9s version --short 2>/dev/null | grep Version | awk '{print \$2}'" "LOG"

    log_info "Installing e1s..."
    install_with_version "e1s" "curl -sL https://raw.githubusercontent.com/keidarcy/e1s-install/master/cloudshell-install.sh | bash" "e1s --version 2>/dev/null | grep 'Current:' | awk '{print \$2}'" "LOG"
}

install_kubernetes_tools

# Container Tools
install_container_tools() {
    log_info "Installing Docker..."
    sudo dnf install -y -q docker >/dev/null
    sudo service docker start
    sudo usermod -aG docker ec2-user

    log_info "Installing SOCI snapshotter ${SOCI_VERSION}..."
    download_and_verify "https://github.com/awslabs/soci-snapshotter/releases/download/v$SOCI_VERSION/soci-snapshotter-$SOCI_VERSION-linux-amd64.tar.gz" "soci-snapshotter-$SOCI_VERSION-linux-amd64.tar.gz" "SOCI snapshotter ${SOCI_VERSION}"
    sudo tar -C /usr/local/bin -xf soci-snapshotter-$SOCI_VERSION-linux-amd64.tar.gz soci soci-snapshotter-grpc
    rm soci-snapshotter-$SOCI_VERSION-linux-amd64.tar.gz

    # Configure Docker for SOCI
    sudo tee /etc/docker/daemon.json >/dev/null << EOF
{
  "experimental": true,
  "features": {
    "containerd-snapshotter": true
  }
}
EOF

    sudo systemctl restart docker
}

install_container_tools

# Utilities
install_utilities() {
    log_info "Installing jq..."
    sudo dnf install -y -q jq >/dev/null

    log_info "Installing yq ${YQ_VERSION}..."
    download_and_verify "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz" "yq_linux_amd64.tar.gz" "yq ${YQ_VERSION}"
    tar xzf yq_linux_amd64.tar.gz && sudo mv yq_linux_amd64 /usr/bin/yq
    rm yq_linux_amd64.tar.gz
}

install_utilities

# Final configuration
log_info "Configuring AWS CLI default region..."
source /etc/profile.d/workshop.sh
aws configure set default.region ${AWS_REGION}

log_info "Base development tools setup completed successfully at $(date)"