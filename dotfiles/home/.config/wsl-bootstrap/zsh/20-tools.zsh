export TERRAGRUNT_TFPATH=tofu
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
export GPG_TTY=$(tty)

# Load GitHub token from pass so gh CLI uses it instead of plain-text hosts.yml
if command -v pass >/dev/null 2>&1; then
  _gh_token="$(pass show gh/github.com 2>/dev/null)"
  if [ -n "$_gh_token" ]; then
    export GH_TOKEN="$_gh_token"
  fi
  unset _gh_token
fi

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi
