# First-time git identity setup — prompts once if user.name or user.email are not configured.
if [[ -z "$(git config --global user.name 2>/dev/null)" ]] || [[ -z "$(git config --global user.email 2>/dev/null)" ]]; then
  echo "🔧 Git identity not configured — let's set it up."
  echo ""

  local _current_name="$(git config --global user.name 2>/dev/null)"
  if [[ -z "$_current_name" ]]; then
    printf "  Your name (e.g. Ashley Kingscote): "
    read -r _git_name
    if [[ -n "$_git_name" ]]; then
      git config --global user.name "$_git_name"
      echo "  ✅ user.name set to: $_git_name"
    else
      echo "  ⚠️  Skipped — run 'git config --global user.name \"Your Name\"' later."
    fi
  fi

  local _current_email="$(git config --global user.email 2>/dev/null)"
  if [[ -z "$_current_email" ]]; then
    printf "  Your email (e.g. you@example.com): "
    read -r _git_email
    if [[ -n "$_git_email" ]]; then
      git config --global user.email "$_git_email"
      echo "  ✅ user.email set to: $_git_email"
    else
      echo "  ⚠️  Skipped — run 'git config --global user.email \"you@example.com\"' later."
    fi
  fi

  echo ""
fi
