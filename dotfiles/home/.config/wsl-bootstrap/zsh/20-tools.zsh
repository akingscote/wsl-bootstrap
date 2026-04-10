export TERRAGRUNT_TFPATH=tofu
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
export GPG_TTY=$(tty)

# Ensure XDG_RUNTIME_DIR points to a user-owned directory with correct
# permissions.  The [boot] command in wsl.conf creates /run/user/<uid> on
# startup, but we export it here so every tool can find it.
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# Start D-Bus and gnome-keyring so tools (gh, copilot CLI, GCM) have a
# Secret Service backend for credential storage.  WSL has no systemd to
# manage these, so we launch them on first interactive shell.
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
  eval $(dbus-launch --sh-syntax 2>/dev/null)
fi
if command -v gnome-keyring-daemon >/dev/null 2>&1 && [ -z "$GNOME_KEYRING_CONTROL" ]; then
  if [ -S "$XDG_RUNTIME_DIR/keyring/control" ]; then
    # Daemon already running from another terminal — just connect.
    eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null)
  else
    # First terminal after WSL boot — prompt for password to unlock keyring.
    echo -n "🔑 Keyring password: "
    read -rs _kr_pass
    echo
    eval $(echo "$_kr_pass" | gnome-keyring-daemon --unlock --replace --components=secrets 2>/dev/null)
    unset _kr_pass
  fi
  export GNOME_KEYRING_CONTROL
fi

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi
