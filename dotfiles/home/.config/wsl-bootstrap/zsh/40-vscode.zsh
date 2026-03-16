if [[ "$TERM_PROGRAM" == "vscode" ]] && command -v code >/dev/null 2>&1; then
  _wsl_bootstrap_code_integration="$(code --locate-shell-integration-path zsh 2>/dev/null || true)"
  if [[ -n "$_wsl_bootstrap_code_integration" && -r "$_wsl_bootstrap_code_integration" ]]; then
    . "$_wsl_bootstrap_code_integration"
  fi
  unset _wsl_bootstrap_code_integration
fi
