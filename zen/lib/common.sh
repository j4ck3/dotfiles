#!/bin/bash
#
# Common utilities for Zen Browser setup scripts
# Shared logging, colors, and configuration paths
#

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration paths
DOTFILES_ZEN_DIR="${DOTFILES_ZEN_DIR:-$HOME/dotfiles/zen}"
CONFIG_DIR="$DOTFILES_ZEN_DIR/config"
ZEN_DIR="$HOME/.zen"
GITHUB_USER="${GITHUB_USER:-j4ck3}"
DOTFILES_REPO="https://github.com/$GITHUB_USER/dotfiles"

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Check if config directory exists
check_config() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_error "Config directory not found: $CONFIG_DIR"
        log_error "Run export.sh on a machine with your Zen Browser setup first."
        exit 1
    fi
    
    if [[ ! -f "$CONFIG_DIR/policies.json" ]]; then
        log_warn "policies.json not found - extensions won't be auto-installed"
    fi
}

# Clone dotfiles repo if needed
clone_dotfiles_if_needed() {
    if [[ -d "$DOTFILES_ZEN_DIR/.git" ]] || [[ -d "$HOME/dotfiles/.git" ]]; then
        log_info "Dotfiles repository already exists"
        return 0
    fi
    
    log_info "Cloning dotfiles repository..."
    if [[ ! -d "$HOME/dotfiles" ]]; then
        git clone "$DOTFILES_REPO" "$HOME/dotfiles" || {
            log_error "Failed to clone dotfiles repository"
            exit 1
        }
        log_success "Dotfiles repository cloned"
    else
        log_info "Dotfiles directory exists but is not a git repository"
    fi
}

