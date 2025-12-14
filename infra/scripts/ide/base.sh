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
# EKSCTL_VERSION="0.220.0"
EKS_NODE_VIEWER_VERSION="0.7.4"

# Container tools
# DOCKER_COMPOSE_VERSION="2.40.2"
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
    retry_critical "$description download" "wget -q '$url' -O '$output'"
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
    retry_critical "npm (latest)" "nvm install-latest-npm"
    retry_critical "CDK and Artillery" "npm install -g aws-cdk artillery"

    # Verify installations
    log_info "Node.js version: $(node -v)"
    log_info "npm version: $(npm -v)"
    log_info "CDK version: $(cdk version)"
    log_info "Artillery version: $(artillery -v)"
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

    log_info "Maven version: $(mvn --version | head -1)"
}

install_maven

# AWS Tools
install_aws_tools() {
    log_info "Installing AWS SAM CLI..."
    download_and_verify "https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-x86_64.zip" "aws-sam-cli-linux-x86_64.zip" "AWS SAM CLI"

    unzip -q aws-sam-cli-linux-x86_64.zip -d sam-installation
    retry_critical "SAM CLI installation" "sudo ./sam-installation/install --update"
    rm -rf ./sam-installation/ aws-sam-cli-linux-x86_64.zip

    log_info "SAM CLI version: $(/usr/local/bin/sam --version)"

    log_info "Installing Session Manager Plugin..."
    download_and_verify "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" "session-manager-plugin.rpm" "Session Manager Plugin"
    retry_critical "Session Manager Plugin" "sudo dnf -q install -y session-manager-plugin.rpm"
    rm session-manager-plugin.rpm
}

install_aws_tools

install_kubernetes_tools() {
    log_info "Installing kubectl ${KUBECTL_VERSION}..."
    download_and_verify "https://s3.us-west-2.amazonaws.com/amazon-eks/${KUBECTL_VERSION}/2025-11-13/bin/linux/amd64/kubectl" "kubectl" "kubectl"

    chmod +x ./kubectl
    mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
    echo "export PATH=\$PATH:\$HOME/bin" | sudo tee -a /etc/profile.d/workshop.sh >/dev/null
    kubectl completion bash >> ~/.bash_completion
    echo "alias k=kubectl" | sudo tee -a /etc/profile.d/workshop.sh >/dev/null
    echo "complete -F __start_kubectl k" >> ~/.bashrc

    log_info "kubectl version: $(kubectl version --client --short 2>/dev/null || echo 'installed')"

    # log_info "Installing eksctl ${EKSCTL_VERSION}..."
    # download_and_verify "https://github.com/weaveworks/eksctl/releases/download/v${EKSCTL_VERSION}/eksctl_Linux_amd64.tar.gz" "eksctl_Linux_amd64.tar.gz" "eksctl"
    # tar -xzf eksctl_Linux_amd64.tar.gz -C /tmp && rm eksctl_Linux_amd64.tar.gz
    # sudo mv /tmp/eksctl /usr/local/bin
    # log_info "eksctl version: $(eksctl version)"

    log_info "Installing Helm ${HELM_VERSION}..."
    retry_critical "Helm ${HELM_VERSION}" "curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3"
    chmod 700 get_helm.sh
    ./get_helm.sh --version v${HELM_VERSION}
    helm completion bash >> ~/.bash_completion
    log_info "Helm version: $(helm version --short)"

    log_info "Installing eks-node-viewer ${EKS_NODE_VIEWER_VERSION}..."
    download_and_verify "https://github.com/awslabs/eks-node-viewer/releases/download/v${EKS_NODE_VIEWER_VERSION}/eks-node-viewer_Linux_x86_64" "eks-node-viewer" "eks-node-viewer"
    chmod +x eks-node-viewer
    sudo mv eks-node-viewer /usr/local/bin

    log_info "Installing k9s..."
    retry_optional "k9s" "curl -sS https://webinstall.dev/k9s | bash"

    log_info "Installing e1s..."
    retry_optional "e1s" "curl -sL https://raw.githubusercontent.com/keidarcy/e1s-install/master/cloudshell-install.sh | bash"
}

install_kubernetes_tools

# Container Tools
install_container_tools() {
    log_info "Installing Docker..."
    sudo dnf install -y -q docker >/dev/null
    sudo service docker start
    sudo usermod -aG docker ec2-user

    # log_info "Installing Docker Compose ${DOCKER_COMPOSE_VERSION}..."
    # DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
    # mkdir -p $DOCKER_CONFIG/cli-plugins
    # download_and_verify "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" "$DOCKER_CONFIG/cli-plugins/docker-compose" "Docker Compose"
    # chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
    # log_info "Docker Compose version: $(docker compose version)"

    log_info "Installing SOCI snapshotter ${SOCI_VERSION}..."
    download_and_verify "https://github.com/awslabs/soci-snapshotter/releases/download/v$SOCI_VERSION/soci-snapshotter-$SOCI_VERSION-linux-amd64.tar.gz" "soci-snapshotter-$SOCI_VERSION-linux-amd64.tar.gz" "SOCI snapshotter"
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
    log_info "jq version: $(jq --version)"

    log_info "Installing yq ${YQ_VERSION}..."
    download_and_verify "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64.tar.gz" "yq_linux_amd64.tar.gz" "yq"
    tar xzf yq_linux_amd64.tar.gz && sudo mv yq_linux_amd64 /usr/bin/yq
    rm yq_linux_amd64.tar.gz
    log_info "yq version: $(yq --version)"
}

install_utilities

# Final configuration
log_info "Configuring AWS CLI default region..."
source /etc/profile.d/workshop.sh
aws configure set default.region ${AWS_REGION}

log_info "Base development tools setup completed successfully at $(date)"