#!/bin/bash
set -e

# Detect the operating system
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$NAME
elif [ -f /etc/lsb-release ]; then
    . /etc/lsb-release
    OS=$DISTRIB_ID
else
    OS=$(uname -s)
fi

# Set the appropriate user based on the detected OS
if [[ "$OS" == "Ubuntu" ]]; then
    USER="ubuntu"
    COMMENT="Setting password for Ubuntu default user"
elif [[ "$OS" == "Amazon Linux" ]]; then
    USER="ec2-user"
    COMMENT="Setting password for Amazon Linux default user"
else
    echo "Unsupported operating system: $OS"
    exit 1
fi

# Check if Homebrew is already installed
if ! command -v brew &> /dev/null; then
    echo "Homebrew not found. Installing Homebrew..."

    # Install Homebrew with better error handling
    export NONINTERACTIVE=1
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || {
        echo "First Homebrew install attempt failed, trying with CI=1..."
        CI=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    }
    
    (echo; echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"') >> ~/.bashrc
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"

    echo "Homebrew installation completed."
else
    echo "Homebrew is already installed."
fi

if [[ "$OS" == "Ubuntu" ]]; then
  sudo apt update && sudo apt install -y sqlite telnet jq strace tree python3 python3-pip gettext bash-completion zsh golang-go plocate
else
  sudo yum update && sudo yum -y install sqlite telnet jq strace tree gcc glibc-static python3 python3-pip gettext bash-completion npm zsh util-linux-user golang-go
  sudo dnf install findutils
fi

#install utils
echo "Installing brew utilities..."
brew install ag || echo "Warning: Failed to install ag"
brew install findutils || echo "Warning: Failed to install findutils"  
brew install fzf || echo "Warning: Failed to install fzf"

#source <(fzf --zsh)

# Install eksdemo with retry logic to handle broken pipe errors
echo "Installing aws/tap/eksdemo..."
for i in {1..3}; do
    if brew install aws/tap/eksdemo; then
        echo "Successfully installed eksdemo"
        break
    else
        echo "Attempt $i failed, retrying in 5 seconds..."
        sleep 5
        if [ $i -eq 3 ]; then
            echo "Failed to install eksdemo after 3 attempts"
            exit 1
        fi
    fi
done

aws configure set cli_pager ""

# start of cloud9-init script
kubectl completion bash >>  ~/.bash_completion
#argocd completion bash >>  ~/.bash_completion
#helm completion bash >>  ~/.bash_completion
echo "alias k=kubectl" >> ~/.bashrc
echo "alias ll='ls -la'" >> ~/.bashrc
echo "alias code=/usr/lib/code-server/bin/code-server" >> ~/.bashrc
echo "complete -F __start_kubectl k" >> ~/.bashrc
curl -sS https://webinstall.dev/k9s | bash

#Install some VsCode plugins
alias code=/usr/lib/code-server/bin/code-server
/usr/lib/code-server/bin/code-server --install-extension hashicorp.terraform
/usr/lib/code-server/bin/code-server --install-extension moshfeu.compare-folders



#git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
#~/.fzf/install --all

curl -sfL https://direnv.net/install.sh | bash
eval "$(direnv hook bash)"

#Install oh-my-zsh zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" || true

echo "continue"

#chsh -s $(which zsh)

# Customize ZSH
git clone https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/themes/powerlevel10k
export ZSH_THEME="powerlevel10k/powerlevel10k"
#p10k configure

git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-history-substring-search ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-history-substring-search

cp .zshrc .p10k.zsh ~/

#Install krew
(
  set -x; cd "$(mktemp -d)" &&
  OS="$(uname | tr '[:upper:]' '[:lower:]')" &&
  ARCH="$(uname -m | sed -e 's/x86_64/amd64/' -e 's/\(arm\)\(64\)\?.*/\1\2/' -e 's/aarch64$/arm64/')" &&
  KREW="krew-${OS}_${ARCH}" &&
  curl -fsSLO "https://github.com/kubernetes-sigs/krew/releases/latest/download/${KREW}.tar.gz" &&
  tar zxvf "${KREW}.tar.gz" &&
  ./"${KREW}" install krew
)
export PATH="${KREW_ROOT:-$HOME/.krew}/bin:$PATH"

kubectl krew install stern


