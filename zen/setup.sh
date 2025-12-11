#!/bin/bash
#
# Zen Browser Setup Script
# Installs Zen Browser and applies your saved configuration from ~/.dotfiles/zen/config/
# Run this on a fresh system to get your browser setup.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
DOTFILES_ZEN_DIR="$HOME/dotfiles/zen"
CONFIG_DIR="$DOTFILES_ZEN_DIR/config"
ZEN_DIR="$HOME/.zen"

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
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# Check if config directory exists and has content
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

# Check for and install yay if needed
check_aur_helper() {
    if command -v yay &> /dev/null; then
        log_success "yay is installed"
        return 0
    fi
    
    if command -v paru &> /dev/null; then
        log_success "paru is installed (will use instead of yay)"
        AUR_HELPER="paru"
        return 0
    fi
    
    log_error "No AUR helper found (yay or paru)"
    log_info "Install yay first:"
    echo ""
    echo "  git clone https://aur.archlinux.org/yay.git"
    echo "  cd yay && makepkg -si"
    echo ""
    exit 1
}

# Install Zen Browser from AUR
install_zen_browser() {
    local aur_helper="${AUR_HELPER:-yay}"
    
    if command -v zen &> /dev/null || [[ -f /usr/bin/zen ]]; then
        log_success "Zen Browser is already installed"
        return 0
    fi
    
    log_info "Installing zen-browser-bin from AUR..."
    $aur_helper -S --noconfirm zen-browser-bin
    
    if command -v zen &> /dev/null || [[ -f /usr/bin/zen ]]; then
        log_success "Zen Browser installed successfully"
    else
        log_error "Zen Browser installation failed"
        exit 1
    fi
}

# Find the Zen Browser installation directory
find_zen_install_dir() {
    local candidates=(
        "/usr/lib/zen-browser"
        "/usr/lib/zen"
        "/opt/zen-browser"
        "/opt/zen"
    )
    
    for dir in "${candidates[@]}"; do
        if [[ -d "$dir" ]]; then
            echo "$dir"
            return 0
        fi
    done
    
    # Try to find it
    local found
    found=$(find /usr/lib /opt -maxdepth 2 -type d -name "zen*" 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        echo "$found"
        return 0
    fi
    
    log_error "Could not find Zen Browser installation directory"
    return 1
}

# Deploy policies.json for extension auto-install
deploy_policies() {
    if [[ ! -f "$CONFIG_DIR/policies.json" ]]; then
        log_warn "No policies.json found, skipping extension setup"
        return 0
    fi
    
    local zen_install_dir
    zen_install_dir=$(find_zen_install_dir)
    
    local distribution_dir="$zen_install_dir/distribution"
    
    log_info "Deploying policies.json to $distribution_dir"
    
    sudo mkdir -p "$distribution_dir"
    sudo cp "$CONFIG_DIR/policies.json" "$distribution_dir/policies.json"
    sudo chmod 644 "$distribution_dir/policies.json"
    
    log_success "Policies deployed - extensions will auto-install on first launch"
}

# Create profile by launching Zen Browser briefly
create_profile() {
    if [[ -d "$ZEN_DIR" ]] && ls "$ZEN_DIR"/*.Default* 1> /dev/null 2>&1; then
        log_info "Zen profile directory already exists"
        return 0
    fi
    
    log_info "Creating Zen Browser profile..."
    log_info "Launching Zen Browser briefly to initialize profile..."
    
    # Launch Zen and wait for profile creation
    timeout 10 zen --headless || true
    
    # Give it a moment
    sleep 2
    
    if [[ -d "$ZEN_DIR" ]]; then
        log_success "Profile directory created"
    else
        log_warn "Profile directory not found - it will be created on first launch"
    fi
}

# Find the default Zen profile directory
find_zen_profile() {
    local profiles_ini="$ZEN_DIR/profiles.ini"
    
    if [[ ! -f "$profiles_ini" ]]; then
        # Profile doesn't exist yet, return empty
        echo ""
        return 0
    fi
    
    # Find the default profile path using awk (handles spaces in path)
    local profile_path=""
    profile_path=$(awk -F= '
        /^\[Install/ { in_install=1 }
        /^\[/ && !/^\[Install/ { in_install=0 }
        in_install && /^Default=/ { print $2; exit }
    ' "$profiles_ini")
    
    if [[ -n "$profile_path" ]]; then
        echo "$ZEN_DIR/$profile_path"
    else
        # Try to find any profile directory
        local found
        found=$(find "$ZEN_DIR" -maxdepth 1 -type d -name "*.Default*" 2>/dev/null | head -1)
        echo "$found"
    fi
}

# Copy configuration files to profile
deploy_config() {
    local profile_dir
    profile_dir=$(find_zen_profile)
    
    if [[ -z "$profile_dir" ]] || [[ ! -d "$profile_dir" ]]; then
        log_warn "Profile directory not found. Configuration will be deployed after first launch."
        log_info "Run this script again after launching Zen Browser once."
        return 0
    fi
    
    log_info "Deploying configuration to: $profile_dir"
    
    # Copy user.js (preferences)
    if [[ -f "$CONFIG_DIR/user.js" ]]; then
        cp "$CONFIG_DIR/user.js" "$profile_dir/user.js"
        log_success "  Copied user.js (preferences)"
    fi
    
    # Copy keyboard shortcuts
    if [[ -f "$CONFIG_DIR/zen-keyboard-shortcuts.json" ]]; then
        cp "$CONFIG_DIR/zen-keyboard-shortcuts.json" "$profile_dir/"
        log_success "  Copied zen-keyboard-shortcuts.json"
    fi
    
    # Copy Zen themes
    if [[ -f "$CONFIG_DIR/zen-themes.json" ]]; then
        cp "$CONFIG_DIR/zen-themes.json" "$profile_dir/"
        log_success "  Copied zen-themes.json"
    fi
    
    # Copy chrome directory (custom CSS)
    if [[ -d "$CONFIG_DIR/chrome" ]]; then
        rm -rf "$profile_dir/chrome"
        cp -r "$CONFIG_DIR/chrome" "$profile_dir/"
        log_success "  Copied chrome/ (custom CSS)"
    fi
    
    # Copy extension preferences
    if [[ -f "$CONFIG_DIR/extension-preferences.json" ]]; then
        cp "$CONFIG_DIR/extension-preferences.json" "$profile_dir/"
        log_success "  Copied extension-preferences.json"
    fi
    
    # Copy extension settings
    if [[ -f "$CONFIG_DIR/extension-settings.json" ]]; then
        cp "$CONFIG_DIR/extension-settings.json" "$profile_dir/"
        log_success "  Copied extension-settings.json"
    fi
    
    # Copy browser-extension-data
    if [[ -d "$CONFIG_DIR/browser-extension-data" ]]; then
        rm -rf "$profile_dir/browser-extension-data"
        cp -r "$CONFIG_DIR/browser-extension-data" "$profile_dir/"
        log_success "  Copied browser-extension-data/"
    fi
    
    # Note about extension storage
    if [[ -d "$CONFIG_DIR/storage" ]]; then
        log_warn "Extension storage data found but not auto-deployed"
        log_info "Extension storage is tied to UUIDs that change per-install."
        log_info "You may need to reconfigure extension settings manually."
    fi
}

# Print summary and next steps
print_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Setup Complete!                           ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo ""
    echo "  1. Launch Zen Browser"
    echo "     Extensions will auto-install from policies.json"
    echo ""
    echo "  2. Wait for extensions to fully load"
    echo "     Some extensions may prompt for permissions"
    echo ""
    echo "  3. Verify your settings"
    echo "     - Keyboard shortcuts should be restored"
    echo "     - Browser preferences should be applied"
    echo ""
    echo "  4. Reconfigure extension-specific settings if needed:"
    echo "     - uBlock Origin: Import backup if you have custom filters"
    echo "     - Vimium C: Re-enter custom keybindings"
    echo "     - Dark Reader: Site-specific settings"
    echo ""
    echo -e "${YELLOW}Tip:${NC} After making changes, run ${CYAN}export.sh${NC} to update your config!"
    echo ""
}

# Main
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║              Zen Browser Setup Script                        ║${NC}"
    echo -e "${BLUE}║          Install & Configure from Dotfiles                   ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    log_step "Step 1: Checking prerequisites"
    check_config
    check_aur_helper
    
    log_step "Step 2: Installing Zen Browser"
    install_zen_browser
    
    log_step "Step 3: Deploying extension policies"
    deploy_policies
    
    log_step "Step 4: Creating browser profile"
    create_profile
    
    log_step "Step 5: Deploying configuration"
    deploy_config
    
    print_summary
}

main "$@"

