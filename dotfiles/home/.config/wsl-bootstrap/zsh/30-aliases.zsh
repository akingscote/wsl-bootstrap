if command -v code-insiders >/dev/null 2>&1; then
  alias code='code-insiders'
fi

alias ti='tofu init'
alias tp='tofu plan'
alias ta='tofu apply -auto-approve'

if command -v uvx >/dev/null 2>&1; then
  alias ampli='uvx --from git+https://github.com/rysweet/amplihack amplihack copilot'
fi

if command -v explorer.exe >/dev/null 2>&1; then
  alias exp='explorer.exe .'
fi
