#!/bin/bash
#
# Zen Browser Config Export Script
# Exports your current Zen Browser settings to ~/.dotfiles/zen/config/
# Run this after making changes in the browser to keep your dotfiles in sync.
#

set -e

# Get script directory and source modules
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/zen-profile.sh"
source "$SCRIPT_DIR/lib/ublock-export.sh"

# Extension ID to AMO slug mapping (for policies.json generation)
declare -A EXTENSION_SLUGS=(
    ["uBlock0@raymondhill.net"]="ublock-origin"
    ["addon@darkreader.org"]="darkreader"
    ["vimium-c@gdh1995.cn"]="vimium-c"
    ["{446900e4-71c2-419f-a6a7-df9c091e268b}"]="bitwarden-password-manager"
    ["sponsorBlocker@ajay.app"]="sponsorblock"
    ["{20fc2e06-e3e4-4b2b-812b-ab431220cada}"]="startpage-private-search"
    ["{7a7a4a92-a2a0-41d1-9fd7-1e92480d612d}"]="styl-us"
    ["idcac-pub@guus.ninja"]="istilldontcareaboutcookies"
    ["enhancerforyoutube@maximerf.addons.mozilla.org"]="enhancer-for-youtube"
    ["floccus@handmadeideas.org"]="floccus"
    ["webextension@metamask.io"]="ether-metamask"
)

# Preferences to exclude (auto-generated, timestamps, internal state)
EXCLUDE_PREFS=(
    "app.update.lastUpdateTime"
    "browser.laterrun.bookkeeping"
    "browser.safebrowsing.provider"
    "browser.sessionstore.upgradeBackup"
    "browser.startup.lastColdStartupCheck"
    "browser.shell.mostRecentDateSetAsDefault"
    "captchadetection"
    "datareporting"
    "devtools.netmonitor.columnsData"
    "distribution.iniFile"
    "doh-rollout"
    "dom.push.userAgentID"
    "extensions.blocklist"
    "extensions.lastAppBuildId"
    "extensions.lastAppVersion"
    "extensions.lastPlatformVersion"
    "extensions.signatureCheckpoint"
    "extensions.systemAddonSet"
    "extensions.webextensions.uuids"
    "idle.lastDailyNotification"
    "media.gmp"
    "nimbus"
    "places.database.lastMaintenance"
    "privacy.purge_trackers"
    "services.settings"
    "services.sync"
    "storage.vacuum"
    "toolkit.profiles.storeID"
    "toolkit.startup.last_success"
    "toolkit.telemetry"
    "zen.mods.last-update"
    "zen.updates.last-build-id"
    "zen.workspaces.active"
)

# Generate policies.json from current extensions
generate_policies() {
    local profile_dir="$1"
    local extensions_json="$profile_dir/extensions.json"
    
    if [[ ! -f "$extensions_json" ]]; then
        log_error "extensions.json not found at $extensions_json"
        return 1
    fi
    
    log_info "Generating policies.json from installed extensions..."
    
    # Start building the policies.json
    local policies='{"policies":{"ExtensionSettings":{'
    local first=true
    
    # Parse extensions.json and extract user-installed extension IDs
    local extension_ids
    extension_ids=$(python3 -c "
import json
import sys

with open('$extensions_json', 'r') as f:
    data = json.load(f)

for addon in data.get('addons', []):
    ext_id = addon.get('id', '')
    # Skip built-in/system extensions
    if '@mozilla.org' in ext_id or '@mozilla.com' in ext_id:
        continue
    # Skip themes
    if addon.get('type') == 'theme':
        continue
    print(ext_id)
")
    
    while IFS= read -r ext_id; do
        [[ -z "$ext_id" ]] && continue
        
        # Get the AMO slug for this extension
        local slug="${EXTENSION_SLUGS[$ext_id]}"
        
        if [[ -z "$slug" ]]; then
            log_warn "No AMO slug mapping for extension: $ext_id (skipping)"
            continue
        fi
        
        local install_url="https://addons.mozilla.org/firefox/downloads/latest/$slug/latest.xpi"
        
        if [[ "$first" == true ]]; then
            first=false
        else
            policies+=','
        fi
        
        # Escape the extension ID for JSON (handle curly braces)
        local escaped_id=$(echo "$ext_id" | sed 's/"/\\"/g')
        policies+="\"$escaped_id\":{\"installation_mode\":\"force_installed\",\"install_url\":\"$install_url\"}"
        
        log_success "  Added: $ext_id -> $slug"
    done <<< "$extension_ids"
    
    policies+='}}}'
    
    # Pretty print and save
    echo "$policies" | python3 -m json.tool > "$CONFIG_DIR/policies.json"
    log_success "Generated policies.json"
}

# Filter and export user preferences
export_user_prefs() {
    local profile_dir="$1"
    local prefs_file="$profile_dir/prefs.js"
    
    if [[ ! -f "$prefs_file" ]]; then
        log_error "prefs.js not found at $prefs_file"
        return 1
    fi
    
    log_info "Exporting user preferences to user.js..."
    
    # Build exclude pattern
    local exclude_pattern=""
    for pref in "${EXCLUDE_PREFS[@]}"; do
        if [[ -n "$exclude_pattern" ]]; then
            exclude_pattern+="|"
        fi
        exclude_pattern+="$pref"
    done
    
    # Filter prefs.js
    {
        echo "// Zen Browser User Preferences"
        echo "// Auto-exported by export.sh on $(date)"
        echo "// Do not edit directly - make changes in browser then run export.sh"
        echo ""
        grep "^user_pref" "$prefs_file" | grep -vE "($exclude_pattern)" | sort
    } > "$CONFIG_DIR/user.js"
    
    local count=$(grep -c "^user_pref" "$CONFIG_DIR/user.js" || echo "0")
    log_success "Exported $count preferences to user.js"
}

# Copy keyboard shortcuts
export_keyboard_shortcuts() {
    local profile_dir="$1"
    local shortcuts_file="$profile_dir/zen-keyboard-shortcuts.json"
    
    if [[ -f "$shortcuts_file" ]]; then
        cp "$shortcuts_file" "$CONFIG_DIR/zen-keyboard-shortcuts.json"
        log_success "Exported keyboard shortcuts"
    else
        log_warn "No keyboard shortcuts file found"
    fi
}

# Copy extension-related files (safe ones only - to public dotfiles)
export_extension_data() {
    local profile_dir="$1"
    
    log_info "Exporting extension metadata (safe files only)..."
    
    # Copy extension preferences (permissions - safe)
    if [[ -f "$profile_dir/extension-preferences.json" ]]; then
        cp "$profile_dir/extension-preferences.json" "$CONFIG_DIR/"
        log_success "  Copied extension-preferences.json"
    fi
    
    # Copy extension settings (command overrides - safe)
    if [[ -f "$profile_dir/extension-settings.json" ]]; then
        cp "$profile_dir/extension-settings.json" "$CONFIG_DIR/"
        log_success "  Copied extension-settings.json"
    fi
}

# Copy Zen-specific theme files
export_zen_themes() {
    local profile_dir="$1"
    
    if [[ -f "$profile_dir/zen-themes.json" ]]; then
        cp "$profile_dir/zen-themes.json" "$CONFIG_DIR/"
        log_success "Exported zen-themes.json"
    fi
    
    if [[ -d "$profile_dir/chrome" ]]; then
        rm -rf "$CONFIG_DIR/chrome"
        cp -r "$profile_dir/chrome" "$CONFIG_DIR/"
        log_success "Exported chrome/ directory (custom CSS)"
    fi
}

# Git auto-commit
git_commit() {
    if [[ ! -d "$DOTFILES_ZEN_DIR/.git" ]] && [[ ! -d "$HOME/dotfiles/.git" ]]; then
        log_warn "No git repository found, skipping auto-commit"
        return 0
    fi
    
    log_info "Committing changes to git..."
    
    cd "$DOTFILES_ZEN_DIR"
    
    # Check if we're in a subdirectory of a git repo
    local git_dir
    git_dir=$(git rev-parse --show-toplevel 2>/dev/null) || true
    
    if [[ -n "$git_dir" ]]; then
        cd "$git_dir"
        git add "$DOTFILES_ZEN_DIR"
        
        if git diff --cached --quiet; then
            log_info "No changes to commit"
        else
            git commit -m "zen: update config $(date '+%Y-%m-%d %H:%M:%S')"
            log_success "Committed changes to git"
        fi
    fi
}

# Main
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║     Zen Browser Config Export Script     ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
    
    # Create config directory if it doesn't exist
    mkdir -p "$CONFIG_DIR"
    
    # Find the profile
    local profile_dir
    profile_dir=$(find_zen_profile)
    
    if [[ -z "$profile_dir" ]] || [[ ! -d "$profile_dir" ]]; then
        log_error "Zen Browser profile not found"
        log_error "Make sure Zen Browser has been launched at least once"
        exit 1
    fi
    
    log_info "Found profile: $profile_dir"
    
    # Check if browser is running
    if pgrep -x "zen" > /dev/null || pgrep -f "zen-browser" > /dev/null; then
        log_warn "Zen Browser appears to be running. For best results, close it first."
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
    
    echo ""
    
    # Export everything
    generate_policies "$profile_dir"
    echo ""
    export_user_prefs "$profile_dir"
    echo ""
    export_keyboard_shortcuts "$profile_dir"
    echo ""
    export_extension_data "$profile_dir"
    echo ""
    export_zen_themes "$profile_dir"
    echo ""
    export_ublock_filters "$profile_dir"
    echo ""
    
    # Git commit
    git_commit
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║           Export Complete!               ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo ""
    echo "Config exported to: $CONFIG_DIR"
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  What was exported:${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "  ✓ policies.json (extension list)"
    echo "  ✓ user.js (browser preferences)"
    echo "  ✓ zen-keyboard-shortcuts.json"
    echo "  ✓ extension-preferences.json"
    echo "  ✓ extension-settings.json"
    echo "  ✓ zen-themes.json"
    echo "  ✓ chrome/ (custom CSS)"
    echo "  ✓ ublock-filters-backup.json (uBlock Origin filters)"
    echo ""
    echo "  All files are git-controlled and can be shared via GitHub."
    echo ""
}

main "$@"
