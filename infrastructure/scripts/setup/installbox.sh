set -e

cd /tmp

echo "Installing Terraform ..."
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform

echo "Installing Argo CD cli"
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd-linux-amd64
sudo mv argocd-linux-amd64 /usr/local/bin/argocd

echo "Installing kubectx"
if [ ! -d /opt/kubectx ]; then
    sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
fi
sudo ln -sf /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -sf /opt/kubectx/kubens /usr/local/bin/kubens

echo "Installing zsh and development tools"
export HOMEBREW_CURL_RETRIES=5
rm -rf /home/ec2-user/.oh-my-zsh
mkdir -p ~/tmp
cd ~/tmp
curl -sSL https://raw.githubusercontent.com/aws-samples/fleet-management-on-amazon-eks-workshop/refs/heads/mainline/hack/.zshrc -o .zshrc
curl -sSL https://raw.githubusercontent.com/aws-samples/fleet-management-on-amazon-eks-workshop/refs/heads/mainline/hack/.p10k.zsh -o .p10k.zsh

# Use the local fixed installbox script
bash ~/java-on-aws/infrastructure/scripts/setup/installbox.sh
