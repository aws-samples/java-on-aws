#bin/sh

start_time=`date +%s`
export init_time=$start_time
~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "Started" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)

download_and_verify () {
  url=$1
  checksum=$2
  out_file=$3

  curl --location --show-error --silent --output $out_file $url

  echo "$checksum $out_file" > "$out_file.sha256"
  sha256sum --check "$out_file.sha256"

  rm "$out_file.sha256"
}

## go to tmp directory
cd /tmp

sudo yum update
sudo yum install -y jq
sudo yum install -y npm

## Ensure AWS CLI v2 is installed
sudo yum -y remove aws-cli
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip -q awscliv2.zip
sudo ./aws/install
rm awscliv2.zip
aws --version

## Set JDK 21 as default
sudo yum -y install java-21-amazon-corretto-devel
sudo update-alternatives --set java /usr/lib/jvm/java-21-amazon-corretto.x86_64/bin/java
sudo update-alternatives --set javac /usr/lib/jvm/java-21-amazon-corretto.x86_64/bin/javac
export JAVA_HOME=/usr/lib/jvm/java-21-amazon-corretto.x86_64
echo "export JAVA_HOME=${JAVA_HOME}" | tee -a ~/.bash_profile
echo "export JAVA_HOME=${JAVA_HOME}" | tee -a ~/.bashrc
java -version

## Install Maven
MVN_VERSION=3.9.6
MVN_FOLDERNAME=apache-maven-${MVN_VERSION}
MVN_FILENAME=apache-maven-${MVN_VERSION}-bin.tar.gz
curl -4 -L https://archive.apache.org/dist/maven/maven-3/${MVN_VERSION}/binaries/${MVN_FILENAME} | tar -xvz
sudo mv $MVN_FOLDERNAME /usr/lib/maven
export M2_HOME=/usr/lib/maven
export PATH=${PATH}:${M2_HOME}/bin
sudo ln -s /usr/lib/maven/bin/mvn /usr/local/bin
/usr/lib/maven/bin/mvn --version

# Install newer version of AWS SAM CLI
wget -q https://github.com/aws/aws-sam-cli/releases/latest/download/aws-sam-cli-linux-x86_64.zip
unzip -q aws-sam-cli-linux-x86_64.zip -d sam-installation
sudo ./sam-installation/install --update
rm -rf ./sam-installation/
rm ./aws-sam-cli-linux-x86_64.zip
/usr/local/bin/sam --version

## Install additional dependencies
sudo npm install -g aws-cdk --force
cdk version
sudo npm install -g artillery

# curl -Lo copilot https://github.com/aws/copilot-cli/releases/latest/download/copilot-linux
# chmod +x copilot
# sudo mv copilot /usr/local/bin/copilot
# copilot --version

wget https://github.com/mikefarah/yq/releases/download/v4.43.1/yq_linux_amd64.tar.gz -O - |\
  tar xz && sudo mv yq_linux_amd64 /usr/bin/yq
yq --version

# Install SOCI related packages and change config
SOCI_VERSION=0.4.0
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
docker info --format '{{json .Driver}}'
docker info --format '{{json .DriverStatus}}'

# Install docker buildx
BUILDX_VERSION=$(curl --silent "https://api.github.com/repos/docker/buildx/releases/latest" |jq -r .tag_name)
curl -JLO "https://github.com/docker/buildx/releases/download/$BUILDX_VERSION/buildx-$BUILDX_VERSION.linux-amd64"
mkdir -p ~/.docker/cli-plugins
mv "buildx-$BUILDX_VERSION.linux-amd64" ~/.docker/cli-plugins/docker-buildx
chmod +x ~/.docker/cli-plugins/docker-buildx
docker run --privileged --rm tonistiigi/binfmt --install all
docker buildx create --use --driver=docker-container

# Install docker compose
# DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
# mkdir -p $DOCKER_CONFIG/cli-plugins
# curl -SL https://github.com/docker/compose/releases/download/v2.26.1/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
# chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose
# docker compose version

## eksctl
# for ARM systems, set ARCH to: `arm64`, `armv6` or `armv7`
ARCH=amd64
PLATFORM=$(uname -s)_$ARCH
curl -sLO "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
# (Optional) Verify checksum
curl -sL "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_checksums.txt" | grep $PLATFORM | sha256sum --check
tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp && rm eksctl_$PLATFORM.tar.gz
sudo mv /tmp/eksctl /usr/local/bin
eksctl version

## kubectl
# https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html
curl -O https://s3.us-west-2.amazonaws.com/amazon-eks/1.30.0/2024-05-12/bin/linux/amd64/kubectl
chmod +x ./kubectl
mkdir -p $HOME/bin && cp ./kubectl $HOME/bin/kubectl && export PATH=$PATH:$HOME/bin
echo 'export PATH=$PATH:$HOME/bin' >> ~/.bashrc
kubectl version --output=yaml

# install Flux
# flux
# flux_version='2.2.3'
# flux_checksum='9a705df552df5ac638f93d7fc43d9d8cda6a78f01a16736ae6f355f4a84ebdb3'
# download_and_verify "https://github.com/fluxcd/flux2/releases/download/v${flux_version}/flux_${flux_version}_linux_amd64.tar.gz" "$flux_checksum" "flux.tar.gz"
# tar zxf flux.tar.gz
# chmod +x flux
# sudo mv ./flux /usr/local/bin
# rm -rf flux.tar.gz
# flux --version

# install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh
helm version

# install eks-node-viewer
wget -O eks-node-viewer https://github.com/awslabs/eks-node-viewer/releases/download/v0.6.0/eks-node-viewer_Linux_x86_64
chmod +x eks-node-viewer
sudo mv -v eks-node-viewer /usr/local/bin

# git config --global user.email "you@workshops.aws"
# git config --global user.name "Your Name"
# git config --global --add --bool push.autoSetupRemote true
# git config --global credential.helper '!aws codecommit credential-helper $@'
# git config --global credential.UseHttpPath true

# curl -O https://bootstrap.pypa.io/get-pip.py
# python3 get-pip.py --user
# rm get-pip.py
# pip install git-remote-codecommit

cd ~/environment
export ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
TOKEN=$(curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
export AWS_REGION=$(curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bash_profile
echo "export ACCOUNT_ID=${ACCOUNT_ID}" | tee -a ~/.bashrc
echo "export CDK_DEFAULT_ACCOUNT=${ACCOUNT_ID}" | tee -a ~/.bash_profile
echo "export CDK_DEFAULT_ACCOUNT=${ACCOUNT_ID}" | tee -a ~/.bashrc
echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
echo "export AWS_REGION=${AWS_REGION}" | tee -a ~/.bashrc
echo "export AWS_DEFAULT_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
echo "export AWS_DEFAULT_REGION=${AWS_REGION}" | tee -a ~/.bashrc
echo "export CDK_DEFAULT_REGION=${AWS_REGION}" | tee -a ~/.bash_profile
echo "export CDK_DEFAULT_REGION=${AWS_REGION}" | tee -a ~/.bashrc
aws configure set default.region ${AWS_REGION}
aws configure get default.region
test -n "$AWS_REGION" && echo AWS_REGION is "$AWS_REGION" || echo AWS_REGION is not set

##  Download & install Session Manager plugin
curl "https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm" -o "session-manager-plugin.rpm"
sudo yum install -y session-manager-plugin.rpm
## Test Session Manager plugin Installation
session-manager-plugin
rm session-manager-plugin.rpm

~/environment/java-on-aws/labs/unicorn-store/infrastructure/scripts/timeprint.sh "setup-ide" $start_time 2>&1 | tee >(cat >> /home/ec2-user/setup-timing.log)
