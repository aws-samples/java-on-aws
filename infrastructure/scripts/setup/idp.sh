set -e

cd /tmp

echo "Installing Terraform ..."
sudo yum install -y yum-utils
sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
sudo yum -y install terraform

echo Installing Argo CD cli
curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd-linux-amd64
sudo mv argocd-linux-amd64 /usr/local/bin/argocd

echo Installing kubectx
sudo git clone https://github.com/ahmetb/kubectx /opt/kubectx
sudo ln -s /opt/kubectx/kubectx /usr/local/bin/kubectx
sudo ln -s /opt/kubectx/kubens /usr/local/bin/kubens

echo Installing zsh
rm -rf /home/ec2-user/.oh-my-zsh
mkdir -p ~/tmp
cd ~/tmp
curl -sSL https://raw.githubusercontent.com/aws-samples/fleet-management-on-amazon-eks-workshop/refs/heads/riv24/hack/.zshrc -o .zshrc
curl -sSL https://raw.githubusercontent.com/aws-samples/fleet-management-on-amazon-eks-workshop/refs/heads/riv24/hack/.p10k.zsh -o .p10k.zsh
curl -sSL https://tinyurl.com/installBox | bash
# sudo usermod -s $(which zsh) $USER
# echo "exec zsh" >> ~/.bashrc
