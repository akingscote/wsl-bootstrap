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
# We use a fixed dbus socket path so all terminals share one session,
# and run gnome-keyring in foreground mode via setsid so it keeps its
# dbus registration after the launching shell exits.
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
  if [ ! -S "$XDG_RUNTIME_DIR/bus" ]; then
    dbus-daemon --session --address="unix:path=$XDG_RUNTIME_DIR/bus" --fork 2>/dev/null
  fi
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  if [ -S "$XDG_RUNTIME_DIR/keyring/control" ]; then
    # Daemon already running from another terminal.
    export GNOME_KEYRING_CONTROL="$XDG_RUNTIME_DIR/keyring"
  else
    # First terminal after WSL boot — prompt for password to unlock keyring.
    echo -n "🔑 Keyring password: "
    read -rs _kr_pass
    echo
    echo "$_kr_pass" | setsid gnome-keyring-daemon --unlock --replace --foreground --components=secrets >/dev/null 2>&1 &
    disown
    unset _kr_pass
    sleep 1
    export GNOME_KEYRING_CONTROL="$XDG_RUNTIME_DIR/keyring"
  fi
fi

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi
