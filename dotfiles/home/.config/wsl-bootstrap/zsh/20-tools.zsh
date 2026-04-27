export TERRAGRUNT_TFPATH=tofu
export DOCKER_HOST="${DOCKER_HOST:-unix:///var/run/docker.sock}"
export GPG_TTY=$(tty)

# XDG_RUNTIME_DIR and D-Bus/keyring setup live in 00-keyring.zsh which is
# sourced before p10k instant prompt (see .zshrc).

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi
