#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

alias ls='ls --color=auto'
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


# misc
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias ll="ls -lah"
alias la="ls -A"
alias l="ls -CF"
alias ds="du -sh ."
alias mkdir="mkdir -pv"

alias dots="cd ~/dotfiles"
alias serve="pnpm dev"

# git
alias gs="git status"
alias ga="git add ."
alias gc="git commit -m"
alias gp="git push"

# system
alias update="sudo pacman -Syu"
alias cleanup="sudo pacman -Rns $(pacman -Qtdq)"

# pnpm
export PNPM_HOME="/home/jacob/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
