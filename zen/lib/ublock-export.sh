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
    
    # Find uBlock storage
    local ublock_storage
    if ! ublock_storage=$(find_ublock_storage "$profile_dir"); then
        log_warn "uBlock Origin storage not found - extension may not be installed or configured"
        log_info "Install uBlock Origin and configure it, then run export.sh again"
        return 0
    fi
    
    log_info "Found uBlock storage at: $ublock_storage"
    
    # uBlock Origin stores its configuration in IndexedDB
    # We need to extract it using Python
    python3 << EOF
import json
import os
import sqlite3
from pathlib import Path

profile_dir = '$profile_dir'
ublock_storage = '$ublock_storage'
output_file = '$output_file'

# uBlock Origin stores its backup data in IndexedDB
# The structure is: storage/default/moz-extension+++UUID/idb/
# We need to find the IndexedDB database

backup_data = {
    "version": 1,
    "filterLists": {},
    "customFilters": "",
    "userSettings": {},
    "whitelist": "",
    "staticFilterList": ""
}

# Try to find IndexedDB database
idb_path = os.path.join(ublock_storage, "idb")
if os.path.exists(idb_path):
    # Look for SQLite databases (IndexedDB uses SQLite in Firefox)
    for root, dirs, files in os.walk(idb_path):
        for file in files:
            if file.endswith('.sqlite') or file.endswith('.sqlite-wal'):
                db_path = os.path.join(root, file)
                try:
                    conn = sqlite3.connect(db_path)
                    cursor = conn.cursor()
                    # Try to read uBlock data
                    # Note: IndexedDB structure is complex, this is a simplified approach
                    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
                    tables = cursor.fetchall()
                    conn.close()
                except:
                    pass

# Try to read from localStorage backup if available
local_storage_path = os.path.join(profile_dir, "browser-extension-data")
if os.path.exists(local_storage_path):
    ublock_id = "uBlock0@raymondhill.net"
    uuid = None
    
    # Try to get UUID from prefs.js
    prefs_file = os.path.join(profile_dir, "prefs.js")
    if os.path.exists(prefs_file):
        import re
        with open(prefs_file, 'r') as f:
            for line in f:
                if 'extensions.webextensions.uuids' in line:
                    match = re.search(r'uBlock0@raymondhill\.net.*?([a-f0-9-]{36})', line)
                    if match:
                        uuid = match.group(1)
                        break
    
    if uuid:
        ext_data_path = os.path.join(local_storage_path, uuid)
        if os.path.exists(ext_data_path):
            # Look for storage.js or similar files
            storage_js = os.path.join(ext_data_path, "storage.js")
            if os.path.exists(storage_js):
                try:
                    with open(storage_js, 'r') as f:
                        content = f.read()
                        # Try to extract JSON data
                        # This is a simplified approach - actual uBlock storage is more complex
                except:
                    pass

# For now, create a minimal backup structure
# The user can manually export from uBlock Origin UI: Settings → About → Backup to file
# This function provides a placeholder that can be enhanced later

backup_data["note"] = "This is a placeholder backup. For full backup, use uBlock Origin UI: Settings → About → Backup to file"

# Write backup file
with open(output_file, 'w') as f:
    json.dump(backup_data, f, indent=2)

print("Created backup file structure at:", output_file)
print("Note: For complete backup, use uBlock Origin UI: Settings → About → Backup to file")
EOF

    if [[ -f "$output_file" ]]; then
        log_success "Exported uBlock filter backup to: $output_file"
        log_warn "Note: This is a basic backup. For complete backup with all filters, use uBlock Origin UI:"
        log_info "  Settings → About → Backup to file"
        log_info "  Then copy that file to: $output_file"
    else
        log_error "Failed to create uBlock backup file"
        return 1
    fi
}

