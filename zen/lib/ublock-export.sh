#!/bin/bash
#
# uBlock Origin filter export functions
# Exports uBlock filter lists to JSON backup format
#

# Find uBlock Origin storage directory
find_ublock_storage() {
    local profile_dir="$1"
    local ublock_id="uBlock0@raymondhill.net"
    
    # Get uBlock UUID
    local ublock_uuid
    ublock_uuid=$(get_extension_uuid "$profile_dir" "$ublock_id")
    
    if [[ -z "$ublock_uuid" ]]; then
        log_warn "uBlock Origin UUID not found - extension may not be installed"
        return 1
    fi
    
    # Try IndexedDB storage first (most common)
    local storage_path="$profile_dir/storage/default/moz-extension+++$ublock_uuid"
    if [[ -d "$storage_path" ]]; then
        echo "$storage_path"
        return 0
    fi
    
    # Try browser-extension-data (localStorage)
    local browser_data_path="$profile_dir/browser-extension-data/$ublock_uuid"
    if [[ -d "$browser_data_path" ]]; then
        echo "$browser_data_path"
        return 0
    fi
    
    return 1
}

# Export uBlock Origin filters to JSON backup format
export_ublock_filters() {
    local profile_dir="$1"
    local output_file="$CONFIG_DIR/ublock-filters-backup.json"
    
    log_info "Exporting uBlock Origin filter lists..."
    
    # Check if uBlock is installed
    local ublock_storage
    if ! ublock_storage=$(find_ublock_storage "$profile_dir"); then
        log_warn "uBlock Origin storage not found - extension may not be installed or configured"
        log_info "Install uBlock Origin and configure it, then run export.sh again"
        return 0
    fi
    
    log_info "Found uBlock storage at: $ublock_storage"
    
    # Check if user has already manually created a backup file
    # Look for common backup file names in Downloads or home directory
    local possible_backups=(
        "$HOME/Downloads/ublock-backup.txt"
        "$HOME/Downloads/ublock-origin-backup.txt"
        "$HOME/ublock-backup.txt"
        "$HOME/.ublock-backup.txt"
    )
    
    local found_backup=""
    for backup in "${possible_backups[@]}"; do
        if [[ -f "$backup" ]] && grep -q '"version"' "$backup" 2>/dev/null; then
            found_backup="$backup"
            log_info "Found existing uBlock backup file: $backup"
            break
        fi
    done
    
    # If found, copy it
    if [[ -n "$found_backup" ]]; then
        cp "$found_backup" "$output_file"
        log_success "Copied existing uBlock backup to: $output_file"
        return 0
    fi
    
    # Otherwise, create instructions file and placeholder
    log_warn "No existing uBlock backup found. Creating placeholder with instructions..."
    
    cat > "$output_file" << 'EOF'
{
  "version": 1,
  "filterLists": {},
  "customFilters": "",
  "userSettings": {},
  "whitelist": "",
  "staticFilterList": "",
  "_instructions": "This is a placeholder. To create a real backup: 1) Open uBlock Origin settings, 2) Go to Settings → About → Backup to file, 3) Save the file, 4) Copy it to this location: ~/dotfiles/zen/config/ublock-filters-backup.json"
}
EOF

    log_success "Created placeholder backup file at: $output_file"
    echo ""
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    log_info "  To create a real uBlock backup:"
    log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    log_info "1. Open Zen Browser"
    log_info "2. Click the uBlock Origin icon → ⚙️ Settings"
    log_info "3. Go to: Settings → About → Backup to file"
    log_info "4. Save the backup file"
    log_info "5. Copy it to: $output_file"
    echo ""
    log_info "Or run this command after creating the backup:"
    log_info "  cp ~/Downloads/ublock-backup.txt $output_file"
    echo ""
}

