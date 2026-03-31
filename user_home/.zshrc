# Prompt: path on one line, arrow on next
PROMPT='%F{blue}%~%f
%F{magenta}➜ %f'

# Reset color before command execution
preexec() {
  printf "\033[0m"
}

export PATH="$HOME/.local/bin:$PATH"
export ENABLE_LSP_TOOL=1
