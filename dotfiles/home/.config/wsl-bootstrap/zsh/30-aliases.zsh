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

alias corpazlogin='AZURE_CORE_LOGIN_EXPERIENCE_V2=false az login --tenant 72f988bf-86f1-41af-91ab-2d7cd011db47 && az account set -s be51a72b-4d76-4627-9a17-7dd26245da7b'

# List only custom aliases defined by wsl-bootstrap
mine() {
  grep -E "^alias " "$HOME/.config/wsl-bootstrap/zsh/30-aliases.zsh" | sed 's/^alias //'
}
