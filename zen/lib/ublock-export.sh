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

# Extract uBlock Origin filters from IndexedDB
extract_ublock_from_indexeddb() {
    local profile_dir="$1"
    local ublock_storage="$2"
    local output_file="$3"
    
    # Find the IndexedDB SQLite file
    local idb_file
    idb_file=$(find "$ublock_storage/idb" -name "*.sqlite" -type f 2>/dev/null | head -1)
    
    if [[ -z "$idb_file" ]] || [[ ! -f "$idb_file" ]]; then
        return 1
    fi
    
    # Use Python to extract uBlock data from IndexedDB
    python3 << EOF
import json
import sqlite3
import os
import struct

idb_file = '$idb_file'
output_file = '$output_file'

try:
    conn = sqlite3.connect(idb_file)
    cursor = conn.cursor()
    
    # Get all object stores
    cursor.execute("SELECT name FROM object_store")
    stores = cursor.fetchall()
    
    backup_data = {
        "version": 1,
        "filterLists": {},
        "customFilters": "",
        "userSettings": {},
        "whitelist": "",
        "staticFilterList": ""
    }
    
    # uBlock stores data in object_data table
    # The keys are base64-encoded, and values are in file_data blob
    cursor.execute("SELECT key, file_data FROM object_data")
    rows = cursor.fetchall()
    
    # Try to find uBlock's storage keys
    # uBlock uses keys like: "0dbdif0dpnqjmfe0qmpxf.1" for different data types
    for key, file_data in rows:
        if not file_data:
            continue
        
        # Try to decode as JSON (uBlock stores JSON data)
        try:
            # The file_data might be prefixed with length or other metadata
            # Try to extract JSON from it
            data_str = file_data.decode('utf-8', errors='ignore')
            
            # Look for JSON-like content
            if '{' in data_str or '[' in data_str:
                # Try to find JSON object
                start = data_str.find('{')
                if start == -1:
                    start = data_str.find('[')
                
                if start != -1:
                    json_str = data_str[start:]
                    # Try to find the end
                    brace_count = 0
                    bracket_count = 0
                    end = start
                    in_string = False
                    escape = False
                    
                    for i, char in enumerate(json_str):
                        if escape:
                            escape = False
                            continue
                        if char == '\\':
                            escape = True
                            continue
                        if char == '"' and not escape:
                            in_string = not in_string
                            continue
                        if in_string:
                            continue
                        if char == '{':
                            brace_count += 1
                        elif char == '}':
                            brace_count -= 1
                        elif char == '[':
                            bracket_count += 1
                        elif char == ']':
                            bracket_count -= 1
                        
                        if brace_count == 0 and bracket_count == 0 and (char == '}' or char == ']'):
                            end = i + 1
                            break
                    
                    if end > start:
                        try:
                            data = json.loads(json_str[:end])
                            # Check if this looks like uBlock data
                            if isinstance(data, dict):
                                if 'filterLists' in data or 'customFilters' in data or 'userSettings' in data:
                                    backup_data.update(data)
                                    break
                        except:
                            pass
        except:
            pass
    
    conn.close()
    
    # Write backup file
    with open(output_file, 'w') as f:
        json.dump(backup_data, f, indent=2)
    
    # Also try to extract static filters as plain text
    static_filters_file = output_file.replace('.json', '-my-static-filters.txt')
    if 'staticFilterList' in backup_data and backup_data['staticFilterList']:
        with open(static_filters_file, 'w') as f:
            f.write(backup_data['staticFilterList'])
        print(f"Static filters exported to: {static_filters_file}")
    
    if 'customFilters' in backup_data and backup_data['customFilters']:
        custom_filters_file = output_file.replace('.json', '-custom-filters.txt')
        with open(custom_filters_file, 'w') as f:
            f.write(backup_data['customFilters'])
        print(f"Custom filters exported to: {custom_filters_file}")
    
    print(f"Backup data exported to: {output_file}")
    
except Exception as e:
    print(f"Error extracting uBlock data: {e}", file=sys.stderr)
    import sys
    sys.exit(1)
EOF
}

# Export uBlock Origin filters to JSON backup format
export_ublock_filters() {
    local profile_dir="$1"
    local output_file="$CONFIG_DIR/ublock-filters-backup.json"
    local static_filters_file="$CONFIG_DIR/ublock-my-static-filters.txt"
    
    log_info "Exporting uBlock Origin filter lists..."
    
    # Check if uBlock is installed
    local ublock_storage
    if ! ublock_storage=$(find_ublock_storage "$profile_dir"); then
        log_warn "uBlock Origin storage not found - extension may not be installed or configured"
        log_info "Install uBlock Origin and configure it, then run export.sh again"
        return 0
    fi
    
    log_info "Found uBlock storage at: $ublock_storage"
    
    # Try to extract from IndexedDB
    log_info "Attempting to extract filters from IndexedDB..."
    if extract_ublock_from_indexeddb "$profile_dir" "$ublock_storage" "$output_file" 2>&1 | while IFS= read -r line; do
        if [[ "$line" == *"exported to:"* ]]; then
            log_success "$line"
        elif [[ "$line" == *"Error"* ]]; then
            log_warn "$line"
        fi
    done; then
        # Check if we got real data (not just empty structure)
        if [[ -f "$output_file" ]] && grep -q '"customFilters":' "$output_file" && ! grep -q '"customFilters": ""' "$output_file"; then
            log_success "Successfully extracted uBlock filters from IndexedDB"
            if [[ -f "$static_filters_file" ]]; then
                log_success "Static filters also exported to: $static_filters_file"
            fi
            return 0
        fi
    fi
    
    # Fallback: Check if user has already manually created a backup file
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
        
        # Also extract static filters if present
        if grep -q '"staticFilterList"' "$output_file"; then
            python3 -c "
import json
with open('$output_file', 'r') as f:
    data = json.load(f)
    if 'staticFilterList' in data and data['staticFilterList']:
        with open('$static_filters_file', 'w') as out:
            out.write(data['staticFilterList'])
            print('Static filters extracted')
" 2>/dev/null && log_success "Static filters extracted to: $static_filters_file"
        fi
        return 0
    fi
    
    # Otherwise, create instructions file and placeholder
    log_warn "Could not extract filters automatically. Creating placeholder with instructions..."
    
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

