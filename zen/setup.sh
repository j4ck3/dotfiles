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
# Detect actual Syncthing volume mount path
# Try to get from environment (set by bootstrap.sh) or detect it
if [[ -z "$SYNC_HOST_PATH" ]]; then
    # Try to detect from docker inspect
    if command -v docker &> /dev/null && docker ps | grep -q syncthing; then
        SYNC_HOST_PATH=$(docker inspect syncthing --format '{{range .Mounts}}{{if eq .Destination "/syncthing"}}{{.Source}}{{end}}{{end}}' 2>/dev/null | head -1)
        if [[ -n "$SYNC_HOST_PATH" ]]; then
            SYNC_HOST_PATH="${SYNC_HOST_PATH}/zen-private"
        fi
    fi
    # Fallback to default
    SYNC_HOST_PATH="${SYNC_HOST_PATH:-$HOME/Sync/zen-private}"
fi
PRIVATE_DIR="$SYNC_HOST_PATH"  # Syncthing-synced private storage

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
    
    # Check multiple possible locations
    local zen_paths=(
        "/usr/bin/zen"
        "/usr/bin/zen-browser"
        "/usr/local/bin/zen"
        "/usr/local/bin/zen-browser"
    )
    
    # Check if already installed
    for path in "${zen_paths[@]}"; do
        if [[ -f "$path" ]]; then
            log_success "Zen Browser is already installed at $path"
            return 0
        fi
    done
    
    if command -v zen &> /dev/null; then
        log_success "Zen Browser is already installed"
        return 0
    fi
    
    log_info "Installing zen-browser-bin from AUR..."
    if ! $aur_helper -S --noconfirm zen-browser-bin; then
        log_error "Failed to install zen-browser-bin package"
        exit 1
    fi
    
    # Wait a moment for installation to complete and PATH to update
    sleep 2
    
    # Check if package is installed
    if ! pacman -Q zen-browser-bin &> /dev/null; then
        log_error "zen-browser-bin package not found after installation"
        exit 1
    fi
    
    log_info "Package installed, verifying binary location..."
    
    # Check all possible locations
    local found=false
    for path in "${zen_paths[@]}"; do
        if [[ -f "$path" ]]; then
            log_success "Zen Browser installed successfully at $path"
            found=true
            break
        fi
    done
    
    # Also check via command
    if [[ "$found" == false ]] && command -v zen &> /dev/null; then
        log_success "Zen Browser installed successfully (found via PATH)"
        found=true
    fi
    
    # Check for zen-browser command
    if [[ "$found" == false ]] && command -v zen-browser &> /dev/null; then
        log_success "Zen Browser installed successfully (found as zen-browser)"
        found=true
    fi
    
    if [[ "$found" == false ]]; then
        log_error "Zen Browser installation verification failed"
        log_info "Package is installed, but binary not found in expected locations:"
        for path in "${zen_paths[@]}"; do
            log_info "  - $path"
        done
        log_info "Checking installed files..."
        pacman -Ql zen-browser-bin | grep -E "bin/zen" | head -5 || true
        exit 1
    fi
}

# Find the Zen Browser binary path
find_zen_binary() {
    # Check common binary locations
    local candidates=(
        "/usr/bin/zen"
        "/usr/bin/zen-browser"
        "/usr/local/bin/zen"
        "/usr/local/bin/zen-browser"
    )
    
    for path in "${candidates[@]}"; do
        if [[ -f "$path" ]] && [[ -x "$path" ]]; then
            echo "$path"
            return 0
        fi
    done
    
    # Check via command
    if command -v zen &> /dev/null; then
        command -v zen
        return 0
    fi
    
    if command -v zen-browser &> /dev/null; then
        command -v zen-browser
        return 0
    fi
    
    # Try to find it via pacman
    local zen_bin
    zen_bin=$(pacman -Ql zen-browser-bin 2>/dev/null | grep -E "/bin/zen" | head -1 | awk '{print $2}') || true
    if [[ -n "$zen_bin" ]] && [[ -f "$zen_bin" ]] && [[ -x "$zen_bin" ]]; then
        echo "$zen_bin"
        return 0
    fi
    
    log_error "Could not find Zen Browser binary"
    return 1
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
    
    # Find the zen binary
    local zen_binary
    if ! zen_binary=$(find_zen_binary); then
        log_warn "Could not find Zen Browser binary - profile will be created on first launch"
        return 0
    fi
    
    log_info "Found Zen Browser at: $zen_binary"
    log_info "Launching Zen Browser briefly to initialize profile..."
    
    # Launch Zen and wait for profile creation
    # Use DISPLAY=:0 to ensure it can run even if no display is set
    timeout 10 env DISPLAY=:0 "$zen_binary" --headless 2>/dev/null || true
    
    # Give it a moment
    sleep 2
    
    if [[ -d "$ZEN_DIR" ]]; then
        log_success "Profile directory created"
    else
        log_warn "Profile directory not found - it will be created on first launch"
        log_info "This is normal if running in a headless environment"
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
    
    # Set Startpage as default search engine
    set_startpage_default "$profile_dir"
}

# Set Startpage as default search engine
set_startpage_default() {
    local profile_dir="$1"
    
    log_info "Setting Startpage as default search engine..."
    
    # Ensure user.js has the preference (it should already be there, but verify)
    if ! grep -q "browser.search.defaultenginename.*Startpage" "$profile_dir/user.js" 2>/dev/null; then
        echo 'user_pref("browser.search.defaultenginename", "Startpage");' >> "$profile_dir/user.js"
        log_info "  Added Startpage preference to user.js"
    fi
    
    # Also set it via the extension ID (the Startpage extension ID)
    # The extension will register the search engine when it loads
    # We need to wait for the extension to install and then set it
    log_info "  Startpage extension will set itself as default when installed"
    log_info "  The SearchEngines policy in policies.json will also configure it"
    log_warn "  Note: You may need to restart the browser after first launch for Startpage to become default"
}

# Import private data from Syncthing folder
import_private_data() {
    local profile_dir
    profile_dir=$(find_zen_profile)
    
    if [[ -z "$profile_dir" ]] || [[ ! -d "$profile_dir" ]]; then
        log_warn "Profile directory not found. Private data will be imported after first launch."
        return 0
    fi
    
    # Check if Syncthing folder exists (try multiple possible paths)
    log_info "Checking for Syncthing folder at: $PRIVATE_DIR"
    if [[ ! -d "$PRIVATE_DIR" ]]; then
        # Try lowercase sync as fallback
        local alt_path="$HOME/sync/zen-private"
        log_info "Not found, trying alternative path: $alt_path"
        if [[ -d "$alt_path" ]]; then
            log_info "Found folder at alternative path: $alt_path"
            PRIVATE_DIR="$alt_path"
        else
            log_warn "Syncthing private folder not found at: $PRIVATE_DIR"
            log_info "Also checked: $alt_path"
            log_info "Checking what's actually in ~/Sync and ~/sync..."
            ls -la ~/Sync/ 2>/dev/null | head -5 || log_info "~/Sync/ does not exist"
            ls -la ~/sync/ 2>/dev/null | head -5 || log_info "~/sync/ does not exist"
            log_info "Make sure Syncthing has synced the zen-private folder"
            log_info "Then run this script again or manually copy the data"
            return 0
        fi
    else
        log_info "Found folder at: $PRIVATE_DIR"
        log_info "Contents: $(ls -1 "$PRIVATE_DIR" 2>/dev/null | head -5 | tr '\n' ' ')"
    fi
    
    # Check if data has been synced
    if [[ ! -f "$PRIVATE_DIR/last-export.txt" ]]; then
        log_warn "No export data found in Syncthing folder: $PRIVATE_DIR"
        log_info "Files in folder:"
        ls -la "$PRIVATE_DIR/" 2>/dev/null | head -10 || log_info "  (folder is empty or inaccessible)"
        log_info "Run export.sh on your main machine first"
        return 0
    fi
    
    local export_date=$(cat "$PRIVATE_DIR/last-export.txt")
    log_info "Importing private data (exported: $export_date)"
    
    # Get the old UUID mapping (from source machine)
    local old_uuid_mapping="$PRIVATE_DIR/uuid-mapping.json"
    
    # Get current UUID mapping (this machine - will be populated after extensions install)
    local current_prefs="$profile_dir/prefs.js"
    
    # Copy browser-extension-data (doesn't need UUID remapping)
    if [[ -d "$PRIVATE_DIR/browser-extension-data" ]]; then
        rm -rf "$profile_dir/browser-extension-data"
        cp -r "$PRIVATE_DIR/browser-extension-data" "$profile_dir/"
        log_success "  Copied browser-extension-data/"
    fi
    
    # Copy extension storage with UUID remapping
    if [[ -d "$PRIVATE_DIR/storage" ]] && [[ -f "$old_uuid_mapping" ]]; then
        log_info "  Importing extension storage with UUID remapping..."
        
        # Check if we have current UUIDs (extensions must be installed first)
        if [[ -f "$current_prefs" ]] && grep -q "extensions.webextensions.uuids" "$current_prefs"; then
            # Extract current UUID mapping
            local current_uuid_json=$(grep 'extensions.webextensions.uuids' "$current_prefs" | \
                sed 's/user_pref("extensions.webextensions.uuids", "\(.*\)");/\1/' | \
                sed 's/\\"/"/g')
            
            # Use Python to do the UUID remapping
            python3 << EOF
import json
import os
import shutil

# Load UUID mappings
with open('$old_uuid_mapping', 'r') as f:
    old_uuids = json.load(f)

current_uuids = json.loads('''$current_uuid_json''')

# Create reverse mapping: old_uuid -> extension_id -> new_uuid
uuid_remap = {}
for ext_id, old_uuid in old_uuids.items():
    if ext_id in current_uuids:
        new_uuid = current_uuids[ext_id]
        uuid_remap[old_uuid] = new_uuid
        print(f"  Mapping: {old_uuid[:8]}... -> {new_uuid[:8]}... ({ext_id})")

# Copy storage directories with remapped names
src_storage = '$PRIVATE_DIR/storage'
dst_storage = '$profile_dir/storage/default'

os.makedirs(dst_storage, exist_ok=True)

for dirname in os.listdir(src_storage):
    src_path = os.path.join(src_storage, dirname)
    if not os.path.isdir(src_path):
        continue
    
    # Check if this directory contains an old UUID that needs remapping
    new_dirname = dirname
    for old_uuid, new_uuid in uuid_remap.items():
        if old_uuid in dirname:
            new_dirname = dirname.replace(old_uuid, new_uuid)
            break
    
    dst_path = os.path.join(dst_storage, new_dirname)
    
    # Remove existing and copy
    if os.path.exists(dst_path):
        shutil.rmtree(dst_path)
    shutil.copytree(src_path, dst_path)

copied_count = 0
for d in os.listdir(src_storage):
    if os.path.isdir(os.path.join(src_storage, d)):
        copied_count += 1

print(f"  Imported {copied_count} storage directories")

# Verify uBlock Origin specifically
if 'uBlock0@raymondhill.net' in old_uuids and 'uBlock0@raymondhill.net' in current_uuids:
    old_uuid = old_uuids['uBlock0@raymondhill.net']
    new_uuid = current_uuids['uBlock0@raymondhill.net']
    ublock_old_dir = f"moz-extension+++{old_uuid}"
    ublock_new_dir = f"moz-extension+++{new_uuid}"
    if os.path.exists(os.path.join(src_storage, ublock_old_dir)):
        if os.path.exists(os.path.join(dst_storage, ublock_new_dir)):
            print(f"  ✓ uBlock Origin storage imported (UUID remapped)")
        else:
            print(f"  ⚠ uBlock Origin storage found but not imported correctly")
EOF
            log_success "  Extension storage imported with UUID remapping"
        else
            log_warn "  Extensions not installed yet - storage import skipped"
            log_info "  Launch browser first, let extensions install, then run setup.sh again"
        fi
    elif [[ -d "$PRIVATE_DIR/storage" ]]; then
        # No UUID mapping available, just copy directly (may not work)
        log_warn "  No UUID mapping found, copying storage directly (may need manual fix)"
        mkdir -p "$profile_dir/storage/default"
        cp -r "$PRIVATE_DIR/storage/"* "$profile_dir/storage/default/" 2>/dev/null || true
    fi
    
    log_success "Private data import complete"
}

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
    
    if [[ -d "$PRIVATE_DIR" ]] && [[ -f "$PRIVATE_DIR/last-export.txt" ]]; then
        echo "  ✓ Extension settings imported from Syncthing"
    else
        echo "  ⚠ Extension settings pending (Syncthing not synced yet)"
    fi
    
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo ""
    echo "  1. Launch Zen Browser"
    echo "  2. Wait for extensions to install and load"
    echo "  3. Restart browser to apply extension settings"
    echo ""
    
    # Check if private data was imported
    if [[ ! -d "$PRIVATE_DIR" ]] || [[ ! -f "$PRIVATE_DIR/last-export.txt" ]]; then
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "${YELLOW}  Note: Private extension data not yet synced${NC}"
        echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "  Waiting for Syncthing to sync: ~/Sync/zen-private/"
        echo ""
        echo "  After Syncthing syncs, run this command to import extension settings:"
        echo ""
        echo "    ~/dotfiles/zen/setup.sh"
        echo ""
    fi
    
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
    
    log_step "Step 6: Importing private data from Syncthing"
    import_private_data
    
    print_summary
}

main "$@"

