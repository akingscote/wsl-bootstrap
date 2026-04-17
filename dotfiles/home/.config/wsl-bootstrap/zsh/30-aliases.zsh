if command -v code-insiders >/dev/null 2>&1; then
  alias code='code-insiders'
fi

alias ti='tofu init'
alias tp='tofu plan'
alias ta='tofu apply -auto-approve'

if command -v explorer.exe >/dev/null 2>&1; then
  alias exp='explorer.exe .'
fi

alias azwhoami='az account show --query "user.name" -o tsv'
