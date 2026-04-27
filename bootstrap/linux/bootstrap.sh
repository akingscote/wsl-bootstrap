#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)
DEFAULT_REPO_ROOT=$(cd -- "$SCRIPT_DIR/../.." >/dev/null 2>&1 && pwd)
REPO_ROOT="$DEFAULT_REPO_ROOT"
TARGET_HOME="${HOME:-/home/ashley}"
TARGET_OWNER="$(id -un)"
TARGET_GROUP="$(id -gn)"
MODE="plan"
RUN_APT=1
RUN_EXTERNAL=1
RUN_DOTFILES=1
BACKUP_STAMP=$(date +%Y%m%d-%H%M%S)

usage() {
  cat <<'USAGE'
Usage: bootstrap.sh [--plan|--apply] [options]

Options:
  --repo-root PATH      Explicit repo root. Defaults to the script parent.
  --home PATH           Target home directory. Defaults to $HOME.
  --owner USER          File owner for copied dotfiles and user-space installers.
  --skip-external       Skip external installers (nvm, uv, Go, tofu, terragrunt, az, agency, pwsh).
  --skip-dotfiles       Skip copying dotfiles into the target home.
  --only-dotfiles       Copy dotfiles only.
  --help                Show this help text.
USAGE
}

log() {
  printf '[wsl-bootstrap] %s\n' "$*"
}

warn() {
  printf '[wsl-bootstrap] WARN: %s\n' "$*" >&2
}

die() {
  printf '[wsl-bootstrap] ERROR: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

run_shell() {
  local snippet=$1
  if [[ "$MODE" == "plan" ]]; then
    log "PLAN: $snippet"
  else
    bash -c "$snippet"
  fi
}

run_target_shell() {
  local snippet=$1
  if [[ "$MODE" == "plan" ]]; then
    log "PLAN(target-home=$TARGET_HOME): $snippet"
  else
    if [[ "$(id -u)" -eq 0 && "$TARGET_OWNER" != "root" ]]; then
      if command_exists runuser; then
        runuser -u "$TARGET_OWNER" -- env HOME="$TARGET_HOME" bash -c "$snippet"
      elif command_exists sudo; then
        sudo -u "$TARGET_OWNER" env HOME="$TARGET_HOME" bash -c "$snippet"
      else
        die "Need runuser or sudo to execute target-user bootstrap steps."
      fi
    else
      HOME="$TARGET_HOME" bash -c "$snippet"
    fi
  fi
}

apply_ownership() {
  local path=$1

  if [[ "$MODE" == "plan" ]]; then
    log "PLAN: chown $TARGET_OWNER:$TARGET_GROUP $path"
    return 0
  fi

  if [[ "$(id -u)" -eq 0 ]]; then
    chown -R "$TARGET_OWNER:$TARGET_GROUP" "$path"
  fi
}

backup_path() {
  local path=$1
  local rel backup_root backup_target

  [[ -e "$path" || -L "$path" ]] || return 0

  rel=${path#"$TARGET_HOME"/}
  if [[ "$rel" == "$path" ]]; then
    rel=$(basename "$path")
  fi

  backup_root="$TARGET_HOME/.local/state/wsl-bootstrap/backups/$BACKUP_STAMP"
  backup_target="$backup_root/$rel"

  if [[ "$MODE" == "plan" ]]; then
    log "PLAN: backup $path -> $backup_target"
    return 0
  fi

  mkdir -p "$(dirname "$backup_target")"
  cp -a "$path" "$backup_target"
}

install_file() {
  local source=$1
  local target=$2

  [[ -r "$source" ]] || die "Missing source file: $source"
  backup_path "$target"

  if [[ "$MODE" == "plan" ]]; then
    log "PLAN: install $target from $source"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  cp "$source" "$target"
  sed -i 's/\r$//' "$target"
  apply_ownership "$target"
}

seed_file_if_missing() {
  local source=$1
  local target=$2

  if [[ -e "$target" || -L "$target" ]]; then
    log "Keeping existing $target"
    return 0
  fi

  install_file "$source" "$target"
}

copy_tree() {
  local source=$1
  local target=$2

  [[ -d "$source" ]] || die "Missing source directory: $source"
  if [[ -d "$target" || -L "$target" ]]; then
    backup_path "$target"
  fi

  if [[ "$MODE" == "plan" ]]; then
    log "PLAN: sync $source -> $target"
    return 0
  fi

  mkdir -p "$(dirname "$target")"
  rm -rf "$target"
  cp -a "$source" "$target"
  find "$target" -type f -exec sed -i 's/\r$//' {} +
  apply_ownership "$target"
}

load_versions() {
  local versions_file="$REPO_ROOT/manifests/tool-versions.env"
  [[ -r "$versions_file" ]] || die "Missing versions file: $versions_file"

  set -a
  # shellcheck disable=SC1090
  . "$versions_file"
  set +a
}

load_apt_packages() {
  local packages_file="$REPO_ROOT/manifests/apt-packages.txt"
  [[ -r "$packages_file" ]] || die "Missing apt package manifest: $packages_file"
  mapfile -t APT_PACKAGES < <(grep -Ev '^[[:space:]]*(#|$)' "$packages_file")
}

install_dotfiles() {
  local source_home="$REPO_ROOT/dotfiles/home"

  install_file "$source_home/.zshrc" "$TARGET_HOME/.zshrc"
  install_file "$source_home/.p10k.zsh" "$TARGET_HOME/.p10k.zsh"
  install_file "$source_home/.gitconfig" "$TARGET_HOME/.gitconfig"
  copy_tree "$source_home/.config/wsl-bootstrap" "$TARGET_HOME/.config/wsl-bootstrap"

  # Install user scripts (e.g. wsl-open for BROWSER support)
  if [[ -d "$source_home/.local/bin" ]]; then
    for script in "$source_home/.local/bin"/*; do
      [[ -f "$script" ]] || continue
      install_file "$script" "$TARGET_HOME/.local/bin/$(basename "$script")"
      chmod +x "$TARGET_HOME/.local/bin/$(basename "$script")"
    done
  fi

  seed_file_if_missing "$source_home/.gitconfig.local.example" "$TARGET_HOME/.gitconfig.local"
}

install_apt_packages() {
  local joined=""

  load_apt_packages
  if [[ ${#APT_PACKAGES[@]} -eq 0 ]]; then
    warn 'No apt packages defined.'
    return 0
  fi

  log "Installing ${#APT_PACKAGES[@]} apt packages (this may take a few minutes)..."
  printf -v joined '%q ' "${APT_PACKAGES[@]}"
  log "Updating package lists..."
  run_shell 'export DEBIAN_FRONTEND=noninteractive; if [[ "$(id -u)" -eq 0 ]]; then apt-get update; else sudo DEBIAN_FRONTEND=noninteractive apt-get update; fi'
  log "Downloading and installing packages..."
  run_shell "export DEBIAN_FRONTEND=noninteractive; if [[ \"\$(id -u)\" -eq 0 ]]; then apt-get install -y $joined; else sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $joined; fi"
}

install_oh_my_zsh() {
  if [[ -d "$TARGET_HOME/.oh-my-zsh" ]]; then
    log 'Oh My Zsh already present.'
    return 0
  fi

  run_target_shell 'RUNZSH=no CHSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended'
}

install_powerlevel10k() {
  if [[ -d "$TARGET_HOME/.oh-my-zsh/custom/themes/powerlevel10k" ]]; then
    log 'Powerlevel10k already present.'
    return 0
  fi

  run_target_shell 'git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$HOME/.oh-my-zsh/custom/themes/powerlevel10k"'
}

install_zsh_syntax_highlighting() {
  if [[ -d "$TARGET_HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting" ]]; then
    log 'zsh-syntax-highlighting already present.'
    return 0
  fi

  run_target_shell 'git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"'
}

install_nvm() {
  if [[ -s "$TARGET_HOME/.nvm/nvm.sh" ]]; then
    log 'nvm already present.'
    return 0
  fi

  run_target_shell 'curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v'"$NVM_VERSION"'/install.sh | bash'
}

install_node() {
  run_target_shell 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; nvm install '"$NODE_VERSION"'; nvm alias default '"$NODE_VERSION"';'
}

install_uv() {
  if [[ -x "$TARGET_HOME/.local/bin/uv" ]] || command_exists uv; then
    log 'uv already present.'
    return 0
  fi

  run_target_shell 'curl -LsSf https://astral.sh/uv/install.sh | INSTALLER_NO_MODIFY_PATH=1 sh'
}

install_go() {
  if command_exists go && go version | grep -q "go$GO_VERSION"; then
    log "Go $GO_VERSION already present."
    return 0
  fi

  run_shell 'tmp_dir=$(mktemp -d) && curl -fsSLo "$tmp_dir/go.tar.gz" "https://go.dev/dl/go'"$GO_VERSION"'.linux-amd64.tar.gz" && if [[ "$(id -u)" -eq 0 ]]; then rm -rf /usr/local/go && tar -C /usr/local -xzf "$tmp_dir/go.tar.gz"; else sudo rm -rf /usr/local/go && sudo tar -C /usr/local -xzf "$tmp_dir/go.tar.gz"; fi && rm -rf "$tmp_dir"'
}

install_tofu() {
  if command_exists tofu && tofu version 2>/dev/null | head -n 1 | grep -q "v$TOFU_VERSION"; then
    log "OpenTofu $TOFU_VERSION already present."
    return 0
  fi

  run_shell 'tmp_dir=$(mktemp -d) && curl -fsSLo "$tmp_dir/tofu.zip" "https://github.com/opentofu/opentofu/releases/download/v'"$TOFU_VERSION"'/tofu_'"$TOFU_VERSION"'_linux_amd64.zip" && unzip -qo "$tmp_dir/tofu.zip" -d "$tmp_dir/out" && if [[ "$(id -u)" -eq 0 ]]; then install -m 0755 "$tmp_dir/out/tofu" /usr/local/bin/tofu; else sudo install -m 0755 "$tmp_dir/out/tofu" /usr/local/bin/tofu; fi && rm -rf "$tmp_dir"'
}

install_terragrunt() {
  if command_exists terragrunt && terragrunt --version 2>/dev/null | grep -q "v$TERRAGRUNT_VERSION"; then
    log "Terragrunt $TERRAGRUNT_VERSION already present."
    return 0
  fi

  run_shell 'tmp_dir=$(mktemp -d) && curl -fsSLo "$tmp_dir/terragrunt" "https://github.com/gruntwork-io/terragrunt/releases/download/v'"$TERRAGRUNT_VERSION"'/terragrunt_linux_amd64" && if [[ "$(id -u)" -eq 0 ]]; then install -m 0755 "$tmp_dir/terragrunt" /usr/local/bin/terragrunt; else sudo install -m 0755 "$tmp_dir/terragrunt" /usr/local/bin/terragrunt; fi && rm -rf "$tmp_dir"'
}

install_azure_cli() {
  if command_exists az; then
    log 'Azure CLI already present.'
    return 0
  fi

  run_shell 'export DEBIAN_FRONTEND=noninteractive; if [[ "$(id -u)" -eq 0 ]]; then curl -sL https://aka.ms/InstallAzureCLIDeb | bash; else curl -sL https://aka.ms/InstallAzureCLIDeb | sudo DEBIAN_FRONTEND=noninteractive bash; fi'
}

install_docker_cli() {
  if command_exists docker; then
    log 'Docker CLI already present.'
    return 0
  fi

  run_shell 'install -m 0755 -d /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc && chmod a+r /etc/apt/keyrings/docker.asc'
  run_shell '. /etc/os-release && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" > /etc/apt/sources.list.d/docker.list'
  run_shell 'export DEBIAN_FRONTEND=noninteractive; apt-get update -qq && apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin'
}

install_cfssl() {
  if command_exists cfssl && command_exists cfssljson; then
    log 'cfssl already present.'
    return 0
  fi

  run_shell 'curl -fsSLo /usr/local/bin/cfssl "https://github.com/cloudflare/cfssl/releases/download/v'"$CFSSL_VERSION"'/cfssl_'"$CFSSL_VERSION"'_linux_amd64" && chmod +x /usr/local/bin/cfssl'
  run_shell 'curl -fsSLo /usr/local/bin/cfssljson "https://github.com/cloudflare/cfssl/releases/download/v'"$CFSSL_VERSION"'/cfssljson_'"$CFSSL_VERSION"'_linux_amd64" && chmod +x /usr/local/bin/cfssljson'
}

install_gcm() {
  if ! command_exists git-credential-manager; then
    run_shell 'tmp_dir=$(mktemp -d) && curl -fsSLo "$tmp_dir/gcm.deb" "https://github.com/git-ecosystem/git-credential-manager/releases/download/v'"$GCM_VERSION"'/gcm-linux-x64-'"$GCM_VERSION"'.deb" && if [[ "$(id -u)" -eq 0 ]]; then DEBIAN_FRONTEND=noninteractive dpkg -i "$tmp_dir/gcm.deb"; else sudo DEBIAN_FRONTEND=noninteractive dpkg -i "$tmp_dir/gcm.deb"; fi && rm -rf "$tmp_dir"'
  else
    log "git-credential-manager already present."
  fi

  # Configure GCM to use the Secret Service backend provided by gnome-keyring.
  run_target_shell 'git config --global credential.credentialStore secretservice'
  run_target_shell 'git config --global credential.helper "$(which git-credential-manager)"'

  # Clear any pre-existing keyring files so gnome-keyring starts with a fresh
  # keyring on first login.  Otherwise a stale locked keyring blocks secret storage.
  run_target_shell 'rm -rf "$HOME/.local/share/keyrings"/*' || true

  # Disable dbus auto-activation of gnome-keyring.  WSL has no login session,
  # so the auto-started daemon would be locked.  Instead, the shell config
  # starts and unlocks the daemon manually with the user's password.
  run_shell 'for f in /usr/share/dbus-1/services/org.gnome.keyring.service /usr/share/dbus-1/services/org.freedesktop.secrets.service /usr/share/dbus-1/services/org.gnome.keyring.SystemPrompter.service /usr/share/dbus-1/services/org.gnome.keyring.PrivatePrompter.service; do [ -f "$f" ] && ! [ -f "${f}.disabled" ] && mv "$f" "${f}.disabled"; done' || true

  # Tell gh CLI to use GCM via the git credential helper.
  # These may fail if gh is not yet authenticated, which is expected at
  # bootstrap time — the user will run "gh auth login" later.
  run_target_shell 'gh config set git_protocol https' || true
  run_target_shell 'gh auth setup-git' || true

  # Initialise pass if it has not been set up yet (useful as a secondary store).
  if ! run_target_shell 'test -d "$HOME/.password-store"'; then
    log 'Initialising pass with a new GPG key...'
    run_target_shell 'gpg --batch --passphrase "" --quick-gen-key "WSL Bootstrap <'"$USER"'@wsl>" default default never'
    local gpg_id
    gpg_id=$(run_target_shell 'gpg --list-keys --with-colons 2>/dev/null | awk -F: "/^pub/{found=1;next} found && /^fpr/{print \$10; exit}"')
    gpg_id=$(echo "$gpg_id" | tr -d '\r')
    run_target_shell 'pass init "'"$gpg_id"'"'
  fi
}

install_copilot_cli() {
  if run_target_shell 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; npm list -g @github/copilot >/dev/null 2>&1'; then
    log 'Copilot CLI already present.'
    return 0
  fi

  run_target_shell 'export NVM_DIR="$HOME/.nvm"; [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"; npm install -g @github/copilot'
}

install_agency() {
  if run_target_shell 'command -v agency >/dev/null 2>&1'; then
    log 'agency already present.'
    return 0
  fi

  run_target_shell 'curl -sSfL https://aka.ms/InstallTool.sh | sh -s agency'
}

install_pwsh() {
  if run_target_shell 'command -v pwsh >/dev/null 2>&1'; then
    log 'PowerShell (pwsh) already present.'
    return 0
  fi

  local release
  release=$(run_shell '. /etc/os-release && echo "$VERSION_ID"')
  run_shell "wget -q 'https://packages.microsoft.com/config/ubuntu/${release}/packages-microsoft-prod.deb' -O /tmp/packages-microsoft-prod.deb && dpkg -i /tmp/packages-microsoft-prod.deb && rm -f /tmp/packages-microsoft-prod.deb && apt-get update -qq && apt-get install -y powershell"
}

install_mise() {
  if [[ -x "$TARGET_HOME/.local/bin/mise" ]] || command_exists mise; then
    log 'mise already present.'
    return 0
  fi

  run_target_shell 'curl -fsSL https://mise.jdx.dev/install.sh | MISE_INSTALL_PATH="$HOME/.local/bin/mise" sh'
}

install_google_chrome() {
  if command_exists google-chrome-stable || command_exists google-chrome; then
    log 'Google Chrome already present.'
    return 0
  fi

  run_shell 'tmp_dir=$(mktemp -d) && curl -fsSLo "$tmp_dir/google-chrome.deb" "https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb" && if [[ "$(id -u)" -eq 0 ]]; then DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp_dir/google-chrome.deb" || (apt-get -f install -y && dpkg -i "$tmp_dir/google-chrome.deb"); else sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$tmp_dir/google-chrome.deb" || (sudo apt-get -f install -y && sudo dpkg -i "$tmp_dir/google-chrome.deb"); fi && rm -rf "$tmp_dir"'
}

ensure_target_shell() {
  if [[ ! -x /usr/bin/zsh ]]; then
    warn 'zsh is not installed yet; leaving the login shell unchanged.'
    return 0
  fi

  if [[ "$MODE" == "plan" ]]; then
    log "PLAN: set login shell for $TARGET_OWNER to /usr/bin/zsh"
    return 0
  fi

  if id "$TARGET_OWNER" >/dev/null 2>&1; then
    if [[ "$(id -u)" -eq 0 ]]; then
      usermod -s /usr/bin/zsh "$TARGET_OWNER"
    else
      chsh -s /usr/bin/zsh "$TARGET_OWNER"
    fi
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --plan)
        MODE="plan"
        ;;
      --apply)
        MODE="apply"
        ;;
      --repo-root)
        shift
        REPO_ROOT=${1:-}
        ;;
      --home)
        shift
        TARGET_HOME=${1:-}
        ;;
      --owner)
        shift
        TARGET_OWNER=${1:-}
        ;;
      --skip-external)
        RUN_EXTERNAL=0
        ;;
      --skip-dotfiles)
        RUN_DOTFILES=0
        ;;
      --only-dotfiles)
        RUN_APT=0
        RUN_EXTERNAL=0
        RUN_DOTFILES=1
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
    shift
  done

  REPO_ROOT=$(cd -- "$REPO_ROOT" >/dev/null 2>&1 && pwd)
  if [[ "$MODE" == "plan" ]]; then
    log "PLAN: ensure target home exists at $TARGET_HOME"
  else
    mkdir -p "$TARGET_HOME"
    mkdir -p "$TARGET_HOME/.config"
    mkdir -p "$TARGET_HOME/.local/bin"
    apply_ownership "$TARGET_HOME"
  fi
  if id "$TARGET_OWNER" >/dev/null 2>&1; then
    TARGET_GROUP=$(id -gn "$TARGET_OWNER")
  fi
  load_versions

  log "Mode: $MODE"
  log "Repo root: $REPO_ROOT"
  log "Target home: $TARGET_HOME"
  log "Target owner: $TARGET_OWNER:$TARGET_GROUP"

  if [[ $RUN_DOTFILES -eq 1 ]]; then
    install_dotfiles
  fi

  if [[ $RUN_APT -eq 1 ]]; then
    install_apt_packages
  fi

  if [[ $RUN_EXTERNAL -eq 1 ]]; then
    log 'Installing Oh My Zsh...'
    install_oh_my_zsh
    log 'Installing Powerlevel10k...'
    install_powerlevel10k
    log 'Installing zsh-syntax-highlighting...'
    install_zsh_syntax_highlighting
    log 'Installing nvm...'
    install_nvm
    log 'Installing Node.js...'
    install_node
    log 'Installing uv...'
    install_uv
    log 'Installing Go...'
    install_go
    log 'Installing OpenTofu...'
    install_tofu
    log 'Installing Terragrunt...'
    install_terragrunt
    log 'Installing Azure CLI...'
    install_azure_cli
    log 'Installing Docker CLI...'
    install_docker_cli
    log 'Installing cfssl...'
    install_cfssl
    log 'Installing Git Credential Manager...'
    install_gcm
    log 'Installing Copilot CLI...'
    install_copilot_cli
    log 'Installing agency...'
    install_agency
    log 'Installing PowerShell (pwsh)...'
    install_pwsh
    log 'Installing mise...'
    install_mise
    log 'Installing Google Chrome...'
    install_google_chrome
  fi

  if [[ $RUN_APT -eq 1 || $RUN_EXTERNAL -eq 1 ]]; then
    ensure_target_shell
  fi

  if [[ "$MODE" == "plan" ]]; then
    log 'Bootstrap plan finished.'
  else
    log 'Bootstrap finished.'
  fi
  log 'Next manual steps: install the Nerd Font on Windows, then run gh auth login and az login inside the distro.'
}

main "$@"
