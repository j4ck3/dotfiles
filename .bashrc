#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias grep='grep --color=auto'
PS1='[\u@\h \W]\$ '
export PATH=$HOME/.dotnet/tools:$PATH

ask() {
  local SYSTEM_PROMPT="You are a helpful assistant. Always answer in a concise, brief way. Only provide essential information."
  local MODEL="${OLLAMA_MODEL:-phi3:latest}"
  local PROMPT="$*"

  : > /tmp/ollama.md

  curl -s http://localhost:11434/api/generate \
    -d "{
      \"model\": \"$MODEL\",
      \"prompt\": \"$PROMPT\",
      \"system\": \"$SYSTEM_PROMPT\",
      \"stream\": true
    }" | jq -r 'select(.response) | .response' | while IFS= read -r chunk; do
      printf "%s" "$chunk" >> /tmp/ollama.md
    done

  glow /tmp/ollama.md
}
alias dots="cd ~/dotfiles"
# misc
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias ls="eza -l --icons"
alias la="eza -la --icons"
alias lt="eza --tree --icons"
alias ds="du -sh ."
alias mkdir="mkdir -pv"
alias vim="nvim"
alias vi="nvim"


# git
alias gs="git status"
alias ga="git add ."
alias gc="git commit -m"
alias gp="git push"

# system
alias update="pacman -Syu"
alias cleanup="pacman -Rns $(pacman -Qtdq)"

# pnpm
export PNPM_HOME="/home/jacob/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end

export PATH="$PATH:/opt/nvim-linux-x86_64/bin"
