export PATH="$HOME/.local/bin:/usr/local/go/bin:$PATH"

if [[ -f "$HOME/.local/bin/env" ]]; then
  . "$HOME/.local/bin/env"
fi

export NVM_DIR="$HOME/.nvm"
if [[ -s "$NVM_DIR/nvm.sh" ]]; then
  . "$NVM_DIR/nvm.sh"
fi
if [[ -s "$NVM_DIR/bash_completion" ]]; then
  . "$NVM_DIR/bash_completion"
fi

export AZURE_CONFIG_DIR="$HOME/.azure-${WSL_DISTRO_NAME}"

# Open URLs on the Windows host via explorer.exe (works for az login, etc.)
export BROWSER=explorer.exe

# Selective Windows interop paths — appendWindowsPath is disabled in wsl.conf
# to prevent Windows tools (e.g. az.cmd) from shadowing Linux binaries.
if [[ -d /mnt/c/Windows/System32 ]]; then
  export PATH="$PATH:/mnt/c/Windows:/mnt/c/Windows/System32"
  for _vscode_bin in /mnt/c/Users/*/AppData/Local/Programs/Microsoft\ VS\ Code{\ Insiders,}/bin(N); do
    export PATH="$PATH:$_vscode_bin"
  done
  unset _vscode_bin
fi
