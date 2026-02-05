#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/functions.sh"

# Architecture detection
if [ -z "$ARCH" ]; then
    ARCH=$(uname -m)
fi

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

echo "Architecture: ARCH=$ARCH, ARCH_UNAME=$ARCH_UNAME, ARCH_K8S=$ARCH_K8S"

# Version definitions (managed by Renovate)
JAVA_VERSION="25"
NVM_VERSION="0.40.3"
NODE_VERSION="20"
MAVEN_VERSION="3.9.11"
KUBECTL_VERSION="1.34.2"
HELM_VERSION="3.19.3"
EKS_NODE_VIEWER_VERSION="0.7.4"
SOCI_VERSION="0.12.0"
YQ_VERSION="4.49.2"

cd /tmp

# libuv io_uring causes issues on some kernels
export UV_USE_IO_URING=0

install_java() {
    log_info "Installing Java versions 8, 17, 21, 25 and setting ${JAVA_VERSION} as default..."
    retry_critical "Java versions (8,17,21,25)" \
        "sudo dnf install -y -q java-1.8.0-amazon-corretto-devel java-17-amazon-corretto-devel java-21-amazon-corretto-devel java-25-amazon-corretto-devel >/dev/null"

    JAVA_ARCH_PATH="java-${JAVA_VERSION}-amazon-corretto.${ARCH_UNAME}"
    sudo update-alternatives --set java /usr/lib/jvm/${JAVA_ARCH_PATH}/bin/java
    sudo update-alternatives --set javac /usr/lib/jvm/${JAVA_ARCH_PATH}/bin/javac

    JAVA_HOME=/usr/lib/jvm/${JAVA_ARCH_PATH}
    echo "export JAVA_HOME=${JAVA_HOME}" | sudo tee -a /etc/profile.d/workshop.sh >/dev/null
    java -version
}

install_nodejs() {
    log_info "Installing Node.js ${NODE_VERSION} and tools..."
    retry_critical "NVM ${NVM_VERSION}" \
        "curl -sS -o- https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh | bash"

    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

    retry_critical "Node.js ${NODE_VERSION}" "nvm install ${NODE_VERSION}"
    install_with_version "npm" "nvm install-latest-npm" "npm --version"
    install_with_version "CDK" "npm install -g aws-cdk" "cdk version"
    install_with_version "Artillery" "npm install -g artillery" "artillery --version | grep 'Artillery:' | awk '{print \$2}'"
}

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

install_aws_tools() {
    log_info "Installing AWS SAM CLI for ${ARCH_SAM}..."
    curl -sS -L "https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-${ARCH_SAM}.zip" -o "aws-sam-cli-linux-${ARCH_SAM}.zip"
    unzip -q aws-sam-cli-linux-${ARCH_SAM}.zip -d sam-installation
    install_with_version "AWS SAM CLI" "sudo ./sam-installation/install --update" "/usr/local/bin/sam --version | awk '{print \$4}'"
    rm -rf ./sam-installation/ aws-sam-cli-linux-${ARCH_SAM}.zip

    log_info "Installing Session Manager Plugin for ${ARCH_UNAME}..."
    if [ "$ARCH_UNAME" = "aarch64" ]; then
        SSM_ARCH="linux_arm64"
    else
        SSM_ARCH="linux_64bit"
    fi
    curl -sS -L "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/${SSM_ARCH}/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
    install_with_version "Session Manager Plugin" "sudo dnf -q install -y session-manager-plugin.rpm" "session-manager-plugin --version 2>/dev/null | head -1"
    rm session-manager-plugin.rpm
}

install_kubernetes_tools() {
    log_info "Installing kubectl ${KUBECTL_VERSION} for ${ARCH_K8S}..."
    download_and_verify "https://s3.us-west-2.amazonaws.com/amazon-eks/${KUBECTL_VERSION}/2025-11-13/bin/linux/${ARCH_K8S}/kubectl" "kubectl" "kubectl ${KUBECTL_VERSION}"
    chmod +x ./kubectl
    mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
    echo "export PATH=\$PATH:\$HOME/bin" | sudo tee -a /etc/profile.d/workshop.sh >/dev/null
    kubectl completion bash >> ~/.bash_completion

    log_info "Installing Helm ${HELM_VERSION}..."
    retry_critical "Helm ${HELM_VERSION}" \
        "curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 && chmod 700 get_helm.sh && ./get_helm.sh --version v${HELM_VERSION}"
    helm completion bash >> ~/.bash_completion

    log_info "Installing eks-node-viewer ${EKS_NODE_VIEWER_VERSION} for ${ARCH_GENERIC}..."
    download_and_verify "https://github.com/awslabs/eks-node-viewer/releases/download/v${EKS_NODE_VIEWER_VERSION}/eks-node-viewer_Linux_${ARCH_GENERIC}" "eks-node-viewer" "eks-node-viewer ${EKS_NODE_VIEWER_VERSION}"
    chmod +x eks-node-viewer
    sudo mv eks-node-viewer /usr/local/bin

    log_info "Installing k9s..."
    export PATH="$HOME/.local/bin:$PATH"
    install_with_version "k9s" "curl -sS https://webinstall.dev/k9s | bash" "k9s version --short 2>/dev/null | grep Version | awk '{print \$2}'" "LOG" || true

    log_info "Installing e1s..."
    E1S_VERSION=$(curl -s https://api.github.com/repos/keidarcy/e1s/releases/latest | jq -r '.tag_name')
    curl -sSLf "https://github.com/keidarcy/e1s/releases/download/${E1S_VERSION}/e1s_${E1S_VERSION#v}_linux_${ARCH_K8S}.tar.gz" -o /tmp/e1s.tar.gz
    tar -xzf /tmp/e1s.tar.gz -C /tmp
    install_with_version "e1s" "cp /tmp/e1s $HOME/.local/bin/ && rm -f /tmp/e1s.tar.gz /tmp/e1s" "e1s --version 2>/dev/null | grep 'Current:' | awk '{print \$2}'" "LOG" || true
}

install_container_tools() {
    log_info "Installing SOCI snapshotter ${SOCI_VERSION} for ${ARCH_K8S}..."
    download_and_verify "https://github.com/awslabs/soci-snapshotter/releases/download/v$SOCI_VERSION/soci-snapshotter-$SOCI_VERSION-linux-${ARCH_K8S}.tar.gz" "soci-snapshotter-$SOCI_VERSION-linux-${ARCH_K8S}.tar.gz" "SOCI snapshotter ${SOCI_VERSION}"
    sudo tar -C /usr/local/bin -xf soci-snapshotter-$SOCI_VERSION-linux-${ARCH_K8S}.tar.gz soci soci-snapshotter-grpc
    rm soci-snapshotter-$SOCI_VERSION-linux-${ARCH_K8S}.tar.gz

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

install_utilities() {
    log_info "Installing yq ${YQ_VERSION} for ${ARCH_YQ}..."
    download_and_verify "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${ARCH_YQ}.tar.gz" "yq_linux_${ARCH_YQ}.tar.gz" "yq ${YQ_VERSION}"
    tar xzf yq_linux_${ARCH_YQ}.tar.gz && sudo mv yq_linux_${ARCH_YQ} /usr/bin/yq
    rm yq_linux_${ARCH_YQ}.tar.gz

    log_info "Installing direnv..."
    install_with_version "direnv" "sudo dnf install -y -q direnv" "direnv version"
    echo 'eval "$(direnv hook bash)"' >> ~/.bashrc
}

install_kiro_cli() {
    log_info "Installing Kiro CLI..."
    retry_optional "Kiro CLI" \
        "curl -fsSL https://cli.kiro.dev/install -o /tmp/kiro_cli_install.sh && bash /tmp/kiro_cli_install.sh"

    if $HOME/.local/bin/kiro --version >/dev/null 2>&1; then
        local version=$($HOME/.local/bin/kiro --version 2>/dev/null | head -1)
        echo "✅ Success: Kiro CLI $version"
    else
        echo "⚠️  Warning: Kiro CLI installation could not be verified"
    fi
}

install_java
install_nodejs
install_maven
install_aws_tools
install_kubernetes_tools
install_container_tools
install_utilities

source /etc/profile.d/workshop.sh
aws configure set default.region ${AWS_REGION}

install_kiro_cli

if [ -f "${SCRIPT_DIR}/shell.sh" ]; then
    log_info "Setting up shell environment..."
    bash "${SCRIPT_DIR}/shell.sh"
fi

log_info "Development tools setup completed"
