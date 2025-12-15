#!/bin/bash
#
# Configuration deployment functions
# Handles deploying all config files to the browser profile
#

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

# Deploy user.js (preferences)
deploy_user_prefs() {
    local profile_dir="$1"
    
    if [[ -f "$CONFIG_DIR/user.js" ]]; then
        cp "$CONFIG_DIR/user.js" "$profile_dir/user.js"
        log_success "  Copied user.js (preferences)"
    fi
}

# Deploy keyboard shortcuts
deploy_keyboard_shortcuts() {
    local profile_dir="$1"
    
    if [[ -f "$CONFIG_DIR/zen-keyboard-shortcuts.json" ]]; then
        cp "$CONFIG_DIR/zen-keyboard-shortcuts.json" "$profile_dir/"
        log_success "  Copied zen-keyboard-shortcuts.json"
    fi
}

# Deploy themes and CSS
deploy_themes() {
    local profile_dir="$1"
    
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
}

# Deploy extension configuration
deploy_extension_config() {
    local profile_dir="$1"
    
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
    
    log_info "  Startpage extension will set itself as default when installed"
    log_info "  The SearchEngines policy in policies.json will also configure it"
    log_warn "  Note: You may need to restart the browser after first launch for Startpage to become default"
}

# Deploy all configuration files
deploy_all_config() {
    local profile_dir
    profile_dir=$(find_zen_profile)
    
    if [[ -z "$profile_dir" ]] || [[ ! -d "$profile_dir" ]]; then
        log_warn "Profile directory not found. Configuration will be deployed after first launch."
        log_info "Run this script again after launching Zen Browser once."
        return 0
    fi
    
    log_info "Deploying configuration to: $profile_dir"
    
    deploy_user_prefs "$profile_dir"
    deploy_keyboard_shortcuts "$profile_dir"
    deploy_themes "$profile_dir"
    deploy_extension_config "$profile_dir"
    set_startpage_default "$profile_dir"
}

