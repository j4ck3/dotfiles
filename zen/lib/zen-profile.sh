#!/bin/bash
#
# Zen Browser profile management functions
# Handles profile detection, creation, and extension UUID lookup
#

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

# Get extension UUID from prefs.js
get_extension_uuid() {
    local profile_dir="$1"
    local extension_id="$2"
    local prefs_file="$profile_dir/prefs.js"
    
    if [[ ! -f "$prefs_file" ]]; then
        return 1
    fi
    
    # Extract UUID mapping from prefs.js
    local uuid_json
    uuid_json=$(grep 'extensions.webextensions.uuids' "$prefs_file" | \
        sed 's/user_pref("extensions.webextensions.uuids", "\(.*\)");/\1/' | \
        sed 's/\\"/"/g') || return 1
    
    # Use Python to extract the UUID for the given extension ID
    python3 -c "
import json
import sys
try:
    uuids = json.loads('''$uuid_json''')
    if '$extension_id' in uuids:
        print(uuids['$extension_id'])
        sys.exit(0)
    else:
        sys.exit(1)
except:
    sys.exit(1)
" 2>/dev/null
}

