#!/bin/bash
#
# Zen Browser Setup Script
# Installs Zen Browser and applies your saved configuration from ~/.dotfiles/zen/config/
# Run this on a fresh system to get your browser setup.
#

set -e

# Get script directory and source modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/zen-install.sh"
source "$SCRIPT_DIR/lib/zen-profile.sh"
source "$SCRIPT_DIR/lib/config-deploy.sh"

# Print summary and next steps
print_summary() {
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                    Setup Complete!                           ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${CYAN}What was configured:${NC}"
    echo ""
    echo "  ✓ Zen Browser installed"
    echo "  ✓ Extensions will auto-install on first launch"
    echo "  ✓ Keyboard shortcuts restored"
    echo "  ✓ Browser preferences applied"
    echo "  ✓ Zen themes applied"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo ""
    echo "  1. Launch Zen Browser"
    echo "  2. Wait for extensions to install and load"
    echo "  3. Configure extension settings manually (if needed)"
    echo "  4. Import uBlock filters: Settings → About → Restore from file"
    echo "     Select: ~/dotfiles/zen/config/ublock-filters-backup.json"
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
    deploy_all_config
    
    print_summary
}

main "$@"
