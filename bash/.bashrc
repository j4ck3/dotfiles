# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source ~/.local/share/omarchy/default/bash/rc

# Add your own exports, aliases, and functions here.
#
# Make an alias for invoking commands you use constantly
# alias p='python'

# pnpm
export PNPM_HOME="/home/jacke/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
export PATH="$PATH:/home/jacke/.dotnet/tools"
export PATH="$PATH:/home/jacke/.dotnet/tools"
export PATH="$PATH:/home/jacke/.dotnet/tools"
export PATH="$HOME/.bun/bin:$PATH"

# ============================================================================
# Custom Aliases
# ============================================================================

# OpenCode alias - run with fast model
alias ask='opencode run -m google/antigravity-gemini-3-flash'

# Navigation aliases
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias ~='cd ~'
alias -- -='cd -'

# List aliases
alias ll='ls -alhF'
alias la='ls -A'
alias l='ls -CF'
alias ls='ls --color=auto'
alias lsd='ls -d */'  # List only directories

# Grep aliases
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# Safety aliases
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

# Remove function - moves files to ~/deleted instead of deleting
remove() {
    mkdir -p ~/deleted
    command mv "$@" ~/deleted/
}

# Quick edit aliases
alias ebash='${EDITOR:-nano} ~/.bashrc'
alias sbash='source ~/.bashrc'

# System info aliases
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ps='ps auxf'
alias psgrep='ps aux | grep -v grep | grep -i -e VSZ -e'

# Git aliases (if git is installed)
if command -v git &> /dev/null; then
    alias gs='git status'
    alias ga='git add'
    alias gc='git commit'
    alias gp='git push'
    alias gl='git log --oneline --graph --decorate'
    alias gd='git diff'
    alias gb='git branch'
    alias gco='git checkout'
fi

# Network aliases
alias ports='netstat -tulanp'
alias ping='ping -c 5'
alias myip='curl -s ifconfig.me'

# Process management
alias htop='htop'
alias top='top'

# History aliases
alias h='history'
alias hgrep='history | grep'

# Directory operations
alias mkdir='mkdir -pv'
alias rmdir='rmdir'

# File operations
alias find='find . -name'
alias ff='find . -type f -name'
alias fd='find . -type d -name'

# Archive operations
alias untar='tar -xvf'
alias targz='tar -czvf'
alias tarbz2='tar -cjvf'

# System update (Arch Linux)
if command -v pacman &> /dev/null; then
    alias update='sudo pacman -Syu'
    alias install='sudo pacman -S'
    alias premove='sudo pacman -Rns'
    alias search='pacman -Ss'
fi
