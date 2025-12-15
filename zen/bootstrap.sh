#!/bin/bash
#
# Zen Browser Bootstrap Script
# Simple entry point: clone repo + install browser
# Run this on a fresh machine to get started.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/j4ck3/dotfiles/master/zen/bootstrap.sh | bash
#   Or: ./bootstrap.sh (if already cloned)
#

set -e

# Colors for basic output (before we can source common.sh)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Detect if script is being piped (curl | bash)
if [[ "${BASH_SOURCE[0]}" == "-" ]] || [[ -z "${BASH_SOURCE[0]}" ]] || [[ ! -f "${BASH_SOURCE[0]}" ]]; then
    # Running via pipe - need to clone repo first
    GITHUB_USER="${GITHUB_USER:-j4ck3}"
    DOTFILES_REPO="https://github.com/$GITHUB_USER/dotfiles"
    DOTFILES_DIR="$HOME/dotfiles"
    
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║          Zen Browser Bootstrap (via curl)                   ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Clone dotfiles if needed
    if [[ ! -d "$DOTFILES_DIR/.git" ]]; then
        echo -e "${BLUE}[INFO]${NC} Cloning dotfiles repository..."
        git clone "$DOTFILES_REPO" "$DOTFILES_DIR" || {
            echo -e "${RED}[ERROR]${NC} Failed to clone dotfiles repository"
            exit 1
        }
        echo -e "${GREEN}[OK]${NC} Dotfiles repository cloned"
    else
        echo -e "${BLUE}[INFO]${NC} Dotfiles repository already exists"
        cd "$DOTFILES_DIR"
        git pull || true
    fi
    
    # Run bootstrap from cloned location
    echo ""
    echo -e "${BLUE}[INFO]${NC} Running bootstrap from cloned repository..."
    exec bash "$DOTFILES_DIR/zen/bootstrap.sh"
    exit 0
fi

# Running directly - source modules normally
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/zen-install.sh"

log_step "Zen Browser Bootstrap"

# Check prerequisites
check_aur_helper

# Clone dotfiles if needed
clone_dotfiles_if_needed

# Install Zen Browser
install_zen_browser

echo ""
log_success "Bootstrap complete!"
echo ""
echo "Next steps:"
echo "  1. Run: ~/dotfiles/zen/setup.sh"
echo "  2. Launch Zen Browser"
echo "  3. Extensions will auto-install on first launch"
echo ""
