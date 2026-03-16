# Managed by wsl-bootstrap. Edit the repo version and rerun bootstrap.

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
  source "$config_file"
done

export AZURE_CONFIG_DIR="$HOME/.azure-${WSL_DISTRO_NAME}"

[[ -f "$HOME/.p10k.zsh" ]] && source "$HOME/.p10k.zsh"
