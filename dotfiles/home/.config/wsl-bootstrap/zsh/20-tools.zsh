export TERRAGRUNT_TFPATH=tofu
export DOCKER_HOST="${DOCKER_HOST:-unix:///run/user/$(id -u)/docker.sock}"
export GPG_TTY=$(tty)

# Ensure XDG_RUNTIME_DIR points to a user-owned directory with correct
# permissions.  The [boot] command in wsl.conf creates /run/user/<uid> on
# startup, but we export it here so every tool can find it.
export XDG_RUNTIME_DIR="/run/user/$(id -u)"

# ---------------------------------------------------------------------------
# D-Bus + gnome-keyring (Secret Service) for credential storage.
#
# WSL has no systemd/PAM login session, so we manage dbus and
# gnome-keyring-daemon ourselves.  The design handles dozens of
# concurrent terminals safely:
#
#   1. A fixed dbus socket at $XDG_RUNTIME_DIR/bus is shared by all shells.
#   2. Only the first shell starts gnome-keyring; others detect it via dbus.
#   3. An atomic mkdir lock prevents races between simultaneous terminals.
#   4. Readiness is confirmed by polling dbus, not socket files or sleeps.
# ---------------------------------------------------------------------------

# Helper: check if a dbus name has an owner on the session bus.
_dbus_name_has_owner() {
  dbus-send --session --print-reply \
    --dest=org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.NameHasOwner "string:$1" 2>/dev/null \
    | grep -q "boolean true"
}

# Helper: wait for a dbus name to appear (up to $1 seconds).
_dbus_wait_for_name() {
  local _name="$1" _timeout="${2:-5}" _i=0
  while [ "$_i" -lt "$_timeout" ]; do
    _dbus_name_has_owner "$_name" && return 0
    sleep 1
    _i=$((_i + 1))
  done
  return 1
}

# --- D-Bus session bus ---
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ] || ! dbus-send --session --print-reply \
      --dest=org.freedesktop.DBus /org/freedesktop/DBus \
      org.freedesktop.DBus.GetId >/dev/null 2>&1; then
  if [ ! -S "$XDG_RUNTIME_DIR/bus" ]; then
    dbus-daemon --session --address="unix:path=$XDG_RUNTIME_DIR/bus" --fork 2>/dev/null
  fi
  export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
fi

# --- gnome-keyring (Secret Service) ---
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  if ! _dbus_name_has_owner "org.freedesktop.secrets"; then
    # No keyring on the bus yet — try to become the one that starts it.
    _lock_dir="$XDG_RUNTIME_DIR/.keyring-init-lock"
    if mkdir "$_lock_dir" 2>/dev/null; then
      # Won the lock — re-check after acquiring (another shell may have
      # started the daemon between our first check and getting the lock).
      if ! _dbus_name_has_owner "org.freedesktop.secrets"; then
        if [ -t 0 ]; then
          echo -n "🔑 Keyring password: "
          read -rs _kr_pass
          echo
          echo "$_kr_pass" | setsid gnome-keyring-daemon --unlock --foreground --components=secrets >/dev/null 2>&1 &
          disown
          unset _kr_pass
          _dbus_wait_for_name "org.freedesktop.secrets" 5
        fi
      fi
      rmdir "$_lock_dir" 2>/dev/null
    else
      # Lost the lock — another terminal is starting the daemon. Wait.
      _dbus_wait_for_name "org.freedesktop.secrets" 10
    fi
    unset _lock_dir
  fi
fi

if command -v mise >/dev/null 2>&1; then
  eval "$(mise activate zsh)"
fi
