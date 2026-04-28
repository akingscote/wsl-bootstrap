# D-Bus + gnome-keyring (Secret Service) for WSL credential storage.
#
# This file MUST be sourced BEFORE powerlevel10k instant prompt because
# it may need to prompt for the keyring password via read(1).  p10k's
# instant prompt captures stdout/stderr and breaks interactive input.
#
# WSL has no systemd/PAM login session, so we manage dbus and
# gnome-keyring-daemon ourselves.  The design handles dozens of
# concurrent terminals safely:
#
#   1. A fixed dbus socket at $XDG_RUNTIME_DIR/bus is shared by all shells.
#   2. Only the first shell starts gnome-keyring; others detect it via dbus.
#   3. An atomic mkdir lock prevents races between simultaneous terminals.
#   4. Readiness is confirmed by polling dbus, not socket files or sleeps.

export XDG_RUNTIME_DIR="/run/user/$(id -u)"

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

# Helper: wait for a dbus name to disappear (up to $1 seconds).
_dbus_wait_for_name_gone() {
  local _name="$1" _timeout="${2:-5}" _i=0
  while [ "$_i" -lt "$_timeout" ]; do
    _dbus_name_has_owner "$_name" || return 0
    sleep 1
    _i=$((_i + 1))
  done
  return 1
}

# --- D-Bus session bus ---
# Always set the address first (fixed, well-known path) so the
# liveness check talks to the right socket.
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
if ! dbus-send --session --print-reply \
      --dest=org.freedesktop.DBus /org/freedesktop/DBus \
      org.freedesktop.DBus.GetId >/dev/null 2>&1; then
  # Bus is dead — clean up stale socket and start fresh
  rm -f "$XDG_RUNTIME_DIR/bus"
  dbus-daemon --session --address="$DBUS_SESSION_BUS_ADDRESS" --fork 2>/dev/null
fi

# --- gnome-keyring (Secret Service) ---
if command -v gnome-keyring-daemon >/dev/null 2>&1; then
  if ! _dbus_name_has_owner "org.freedesktop.secrets"; then
    # No keyring on the bus yet — try to become the one that starts it.
    _lock_dir="$XDG_RUNTIME_DIR/.keyring-init-lock"
    if mkdir "$_lock_dir" 2>/dev/null; then
      # Clean up lock on interrupt/exit
      trap 'rmdir "$_lock_dir" 2>/dev/null' INT TERM EXIT

      # Won the lock — re-check after acquiring (another shell may have
      # started the daemon between our first check and getting the lock).
      if ! _dbus_name_has_owner "org.freedesktop.secrets"; then
        if [ -t 0 ]; then
          _keyring_dir="$HOME/.local/share/keyrings"
          _kr_stderr="$XDG_RUNTIME_DIR/.keyring-unlock-stderr"
          _kr_passfile="$XDG_RUNTIME_DIR/.keyring-pass"
          _kr_unlocked=false

          if [ -f "$_keyring_dir/login.keyring" ]; then
            # --- Existing keyring: validate password ---
            _kr_attempts=0
            while [ "$_kr_attempts" -lt 3 ]; do
              echo -n "🔑 Keyring password: "
              read -rs _kr_pass || { echo; break; }
              echo

              cp "$_keyring_dir/login.keyring" "$_keyring_dir/login.keyring.bak"

              # Write password to file (no trailing newline) and redirect stdin
              # to get a reliable $! PID (pipelines give subshell PIDs in zsh).
              printf '%s' "$_kr_pass" > "$_kr_passfile"
              gnome-keyring-daemon --unlock --foreground --components=secrets \
                < "$_kr_passfile" >/dev/null 2>"$_kr_stderr" &
              _kr_pid=$!

              if _dbus_wait_for_name "org.freedesktop.secrets" 5 && \
                 ! grep -q "failed to unlock" "$_kr_stderr" 2>/dev/null; then
                echo "✅ Keyring unlocked."
                _kr_unlocked=true
                disown "$_kr_pid" 2>/dev/null
                break
              else
                echo "❌ Incorrect keyring password."
                kill -9 "$_kr_pid" 2>/dev/null
                sleep 1
                # Restore original keyring (daemon re-keys on wrong password)
                mv -f "$_keyring_dir/login.keyring.bak" "$_keyring_dir/login.keyring"
                _dbus_wait_for_name_gone "org.freedesktop.secrets" 3
                _kr_attempts=$((_kr_attempts + 1))
              fi
            done

            if [ "$_kr_unlocked" = false ]; then
              echo "⚠️  Max attempts reached. Keyring not unlocked."
            fi
            rm -f "$_keyring_dir/login.keyring.bak"
            unset _kr_attempts _kr_pid
          else
            # --- First time: set password with confirmation ---
            while true; do
              echo -n "🔑 Set keyring password: "
              read -rs _kr_pass || { echo; break; }
              echo
              echo -n "🔑 Confirm password: "
              read -rs _kr_pass2 || { echo; break; }
              echo
              if [ "$_kr_pass" = "$_kr_pass2" ]; then
                break
              fi
              echo "❌ Passwords do not match. Try again."
            done
            unset _kr_pass2

            printf '%s' "$_kr_pass" > "$_kr_passfile"
            gnome-keyring-daemon --unlock --foreground --components=secrets \
              < "$_kr_passfile" >/dev/null 2>&1 &
            _kr_pid=$!
            if _dbus_wait_for_name "org.freedesktop.secrets" 5; then
              echo "✅ Keyring created and unlocked."
              disown "$_kr_pid" 2>/dev/null
            else
              echo "⚠️  Keyring daemon failed to start."
            fi
            unset _kr_pid
          fi

          unset _kr_pass _kr_stderr _keyring_dir _kr_unlocked
          rm -f "$XDG_RUNTIME_DIR/.keyring-unlock-stderr" "$XDG_RUNTIME_DIR/.keyring-pass"
        fi
      fi
      rmdir "$_lock_dir" 2>/dev/null
      trap - INT TERM EXIT
    else
      # Lost the lock — another terminal is starting the daemon. Wait.
      _dbus_wait_for_name "org.freedesktop.secrets" 10
    fi
    unset _lock_dir
  fi
fi
