#!/bin/bash
set -e

# =============================================================================
# Shell UX Setup (zsh + oh-my-zsh + powerlevel10k + fzf)
# =============================================================================

log_info() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_info "Installing zsh and dependencies..."
sudo dnf install -y -q zsh util-linux-user >/dev/null

log_info "Setting zsh as default shell..."
sudo chsh -s /bin/zsh ec2-user

log_info "Installing oh-my-zsh..."
rm -rf ~/.oh-my-zsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

log_info "Installing Powerlevel10k theme..."
git clone --depth=1 -q https://github.com/romkatv/powerlevel10k.git ~/.oh-my-zsh/custom/themes/powerlevel10k

log_info "Installing zsh plugins..."
git clone --depth=1 -q https://github.com/zsh-users/zsh-autosuggestions ~/.oh-my-zsh/custom/plugins/zsh-autosuggestions
git clone --depth=1 -q https://github.com/zsh-users/zsh-syntax-highlighting ~/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting

log_info "Installing fzf..."
rm -rf ~/.fzf
git clone --depth=1 -q https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install --all --no-bash --no-fish >/dev/null

log_info "Creating .zshrc..."
cat > ~/.zshrc << 'EOF'
# Powerlevel10k instant prompt
typeset -g POWERLEVEL9K_INSTANT_PROMPT=quiet
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH=$HOME/.oh-my-zsh
ZSH_THEME="powerlevel10k/powerlevel10k"
DISABLE_UPDATE_PROMPT="true"
DISABLE_UNTRACKED_FILES_DIRTY="true"

plugins=(git docker kubectl zsh-syntax-highlighting zsh-autosuggestions)

source $ZSH/oh-my-zsh.sh

# fzf integration
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

# Powerlevel10k config
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Source workshop env vars (must be before kubectl completion)
[ -f /etc/profile.d/workshop.sh ] && source /etc/profile.d/workshop.sh

# Basic aliases
alias ll='ls -la'
alias k=kubectl

# Dynamic code alias - detect installed IDE and use correct CLI
if [ -d "/home/ec2-user/.local/lib/code-editor-"* ]; then
    # AWS Code Editor - use remote-cli for opening files in running instance
    alias code="$(echo /home/ec2-user/.local/lib/code-editor-*/dist/bin/remote-cli/code)"
elif command -v code-server &>/dev/null; then
    # code-server
    alias code=/usr/lib/code-server/bin/code-server
fi

# kubectl completion
source <(kubectl completion zsh)
compdef k=kubectl

# Source user-specific env vars from bashrc.d
if [ -d ~/.bashrc.d ]; then
  for rc in ~/.bashrc.d/*; do
    [ -f "$rc" ] && . "$rc"
  done
fi
eval "$(direnv hook zsh)"
EOF

log_info "Copying .p10k.zsh..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "${SCRIPT_DIR}/shell-p10k.zsh" ~/.p10k.zsh

log_info "Configuring IDE to use zsh..."
# Check both code-server and code-editor settings.json paths
for settings_path in \
    "$HOME/.local/share/code-server/User/settings.json" \
    "$HOME/.code-editor-server/data/User/settings.json"; do
    if [ -f "$settings_path" ]; then
        log_info "Updating $settings_path for zsh terminal..."
        jq '. + {"terminal.integrated.defaultProfile.linux": "zsh"}' \
            "$settings_path" > /tmp/settings.json \
            && mv /tmp/settings.json "$settings_path"
        break
    fi
done

log_info "Shell setup completed successfully"
