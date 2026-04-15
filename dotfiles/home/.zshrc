# Managed by wsl-bootstrap. Edit the repo version and rerun bootstrap.

# Keyring init runs before p10k instant prompt because it may need to
# prompt for a password via read(1).  p10k's instant prompt captures
# stdout/stderr and breaks interactive console input.
if [[ -f "$HOME/.config/wsl-bootstrap/zsh/00-keyring.zsh" ]]; then
  source "$HOME/.config/wsl-bootstrap/zsh/00-keyring.zsh"
fi

# Git identity prompt also needs interactive I/O before p10k.
if [[ -f "$HOME/.config/wsl-bootstrap/zsh/15-git.zsh" ]]; then
  source "$HOME/.config/wsl-bootstrap/zsh/15-git.zsh"
fi

if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="powerlevel10k/powerlevel10k"
POWERLEVEL10K_MODE="nerdfont-complete"
plugins=(git dnf zsh-syntax-highlighting)

if [[ -s "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
fi

for config_file in "$HOME"/.config/wsl-bootstrap/zsh/*.zsh(.N); do
  [[ "${config_file:t}" == 00-keyring.zsh ]] && continue
  [[ "${config_file:t}" == 15-git.zsh ]] && continue
  source "$config_file"
done

export AZURE_CONFIG_DIR="$HOME/.azure-${WSL_DISTRO_NAME}"

[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
