set -e

cd /tmp

# temporarily disable the libuv use of io_uring https://github.com/amazonlinux/amazon-linux-2023/issues/840
export UV_USE_IO_URING=0

# echo "Installing additional packages ..."
# sudo dnf install -y jq

echo "Installing AWS SAM CLI ..."
wget -q https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-x86_64.zip
unzip -q aws-sam-cli-linux-x86_64.zip -d sam-installation
sudo ./sam-installation/install --update
rm -rf ./sam-installation/
rm ./aws-sam-cli-linux-x86_64.zip
/usr/local/bin/sam --version

echo "Installing nodejs and tools ..."
curl -sS -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.2/install.sh | bash
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
nvm install --lts
node -v
nvm install-latest-npm
npm -v
npm install -g aws-cdk
cdk version
npm install -g artillery
artillery -v

echo "Installing Java 8, 17 and 21 and setting 21 as default ..."
sudo dnf install -y -q java-1.8.0-amazon-corretto-devel >/dev/null
java -version
sudo dnf install -y -q java-17-amazon-corretto-devel >/dev/null
java -version
sudo dnf install -y -q java-21-amazon-corretto-devel >/dev/null
java -version
sudo update-alternatives --set java /usr/lib/jvm/java-21-amazon-corretto.x86_64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-21-amazon-corretto.x86_64/bin/javac
JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto.x86_64
echo "export JAVA_HOME=${JAVA_HOME}" | sudo tee -a /etc/profile.d/workshop.sh
java -version

echo "Installing Maven ..."
MVN_VERSION=3.9.9
MVN_FOLDERNAME=apache-maven-${MVN_VERSION}
MVN_FILENAME=apache-maven-${MVN_VERSION}-bin.tar.gz
curl -sS -4 -L https://archive.apache.org/dist/maven/maven-3/${MVN_VERSION}/binaries/${MVN_FILENAME} | tar -xz
sudo mv $MVN_FOLDERNAME /usr/lib/maven
echo "export M2_HOME=/usr/lib/maven" | sudo tee -a /etc/profile.d/workshop.sh
echo "export PATH=${PATH}:${M2_HOME}/bin" | sudo tee -a /etc/profile.d/workshop.sh
sudo ln -s /usr/lib/maven/bin/mvn /usr/local/bin
mvn --version

echo "Installing yq ..."
wget -nv https://github.com/mikefarah/yq/releases/download/v4.45.1/yq_linux_amd64.tar.gz -O - |\
  tar xz && sudo mv yq_linux_amd64 /usr/bin/yq
yq --version

echo "Installing SOCI related packages and change config ..."
SOCI_VERSION=0.8.0
wget -q https://github.com/awslabs/soci-snapshotter/releases/download/v$SOCI_VERSION/soci-snapshotter-$SOCI_VERSION-linux-amd64.tar.gz
sudo tar -C /usr/local/bin -xvf soci-snapshotter-$SOCI_VERSION-linux-amd64.tar.gz soci soci-snapshotter-grpc
cat << EOF | sudo tee /etc/docker/daemon.json
{
  "experimental": true,
  "features": {
    "containerd-snapshotter": true
  }
}
EOF

sudo systemctl restart docker
# docker info --format '{{json .Driver}}'
# docker info --format '{{json .DriverStatus}}'

# echo "Installing docker buildx ..."
# BUILDX_VERSION=$(curl --silent "https://api.github.com/repos/docker/buildx/releases/latest" |jq -r .tag_name)
# curl -sS -JLO "https://github.com/docker/buildx/releases/download/$BUILDX_VERSION/buildx-$BUILDX_VERSION.linux-amd64"
# mkdir -p ~/.docker/cli-plugins
# mv "buildx-$BUILDX_VERSION.linux-amd64" ~/.docker/cli-plugins/docker-buildx
# chmod +x ~/.docker/cli-plugins/docker-buildx
# docker run --privileged --rm tonistiigi/binfmt --install all
# docker buildx create --use --driver=docker-container

echo "Installing docker compose ..."
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.33.1/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
docker compose version

echo "Installing kubectl ..."
# https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html
curl -sS -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.33.0/2025-05-01/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
echo "export PATH=$PATH:$HOME/bin" | sudo tee -a /etc/profile.d/workshop.sh
kubectl version --client --output=yaml
kubectl completion bash >>  ~/.bash_completion
echo "alias k=kubectl" | sudo tee -a /etc/profile.d/workshop.sh
echo "complete -F __start_kubectl k" >> ~/.bashrc

echo "Installing eks-node-viewer ..."
wget -nv -O eks-node-viewer https://github.com/awslabs/eks-node-viewer/releases/download/v0.7.1/eks-node-viewer_Linux_x86_64
chmod +x eks-node-viewer
sudo mv -v eks-node-viewer /usr/local/bin

echo "Installing eksctl ..."
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sS -sLO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
# (Optional) Verify checksum
curl -sS -sL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin
eksctl version

echo "Installing Helm ..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm version
helm completion bash >>  ~/.bash_completion

echo "Installing k9s ..."
curl -sS https://webinstall.dev/k9s | bash

echo "Installing e1s ... "
curl -sL https://raw.githubusercontent.com/keidarcy/e1s-install/master/cloudshell-install.sh | bash

echo "Installing Session Manager plugin ..."
curl -sS "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
sudo yum -q install -y session-manager-plugin.rpm
session-manager-plugin
rm session-manager-plugin.rpm

# echo "Installing Q Cli ..."
# curl --proto '=https' --tlsv1.2 -sSf "https://desktop-release.codewhisperer.us-east-1.amazonaws.com/latest/q-x86_64-linux.zip" -o /home/ec2-user/q.zip
# unzip /home/ec2-user/q.zip -d /home/ec2-user/
# chmod +x /home/ec2-user/q/install.sh
# sudo Q_INSTALL_GLOBAL=1 /home/ec2-user/q/install.sh

# echo "Fixing bash-preexec errors in Amazon Q shell integration..."
# # Run the fix script from the same directory
# bash "$(dirname "$0")/fix-bash-preexec.sh"

# echo "Installing Kiro CLI (optional) ..."
# if curl -fsSL https://cli.kiro.dev/install | bash 2>&1 | tee /tmp/kiro-install.log; then
#     echo "alias kc='AMAZON_Q_SIGV4=1 kiro-cli'" | sudo tee -a /etc/profile.d/workshop.sh
#     echo "Kiro CLI installed successfully"
# else
#     echo "⚠️  Kiro CLI installation failed (optional component)"
#     echo "Installation log saved to /tmp/kiro-install.log"
# fi || true

# Installing Q CLI (with error handling)
echo "Installing Q CLI..."

{
    curl --proto '=https' --tlsv1.2 -sSf "https://desktop-release.codewhisperer.us-east-1.amazonaws.com/latest/q-x86_64-linux.zip" -o /home/ec2-user/q.zip && \
    unzip -q /home/ec2-user/q.zip -d /home/ec2-user/ && \
    chmod +x /home/ec2-user/q/install.sh && \
    sudo Q_INSTALL_GLOBAL=1 /home/ec2-user/q/install.sh && \
    echo "✓ Q CLI installed successfully"

    # Fix bash-preexec if install succeeded
    if [ -f "$(dirname "$0")/fix-bash-preexec.sh" ]; then
        bash "$(dirname "$0")/fix-bash-preexec.sh" || echo "⚠ Warning: bash-preexec fix failed (non-critical)"
    fi

    # Add Q CLI alias
    echo "alias qc='AMAZON_Q_SIGV4=1 q chat'" | sudo tee -a /etc/profile.d/workshop.sh >/dev/null
    echo "✓ Q CLI alias 'qc' added"
} || echo "⚠ Warning: Q CLI installation failed (non-critical)"

# Cleanup (always runs)
rm -f /home/ec2-user/q.zip 2>/dev/null || true
rm -rf /home/ec2-user/q 2>/dev/null || true

echo "Continuing with setup..."

echo "Installing Spring CLI (optional) ..."
if curl -L https://repo.maven.apache.org/maven2/org/springframework/boot/spring-boot-cli/3.5.0/spring-boot-cli-3.5.0-bin.zip -o /home/ec2-user/spring-boot-cli-3.5.0-bin.zip 2>/dev/null; then
    unzip -q /home/ec2-user/spring-boot-cli-3.5.0-bin.zip -d /home/ec2-user 2>/dev/null || true
    echo "Spring CLI installed successfully"
else
    echo "⚠️  Spring CLI download failed (optional component)"
fi || true

source /etc/profile.d/workshop.sh
aws configure set default.region ${AWS_REGION}
aws configure get default.region

# env

echo "IDE setup is complete."
