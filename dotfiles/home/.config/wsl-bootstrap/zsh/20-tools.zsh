export TERRAGRUNT_TFPATH=tofu
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
export GPG_TTY=$(tty)

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi
