#!/bin/bash
#
# Extract uBlock Origin static filters from backup file
# Usage: ./extract-ublock-filters.sh [backup-file]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

CONFIG_DIR="$SCRIPT_DIR/../config"
BACKUP_FILE="${1:-$CONFIG_DIR/ublock-filters-backup.json}"
STATIC_FILTERS_FILE="$CONFIG_DIR/ublock-my-static-filters.txt"
CUSTOM_FILTERS_FILE="$CONFIG_DIR/ublock-custom-filters.txt"

if [[ ! -f "$BACKUP_FILE" ]]; then
    log_error "Backup file not found: $BACKUP_FILE"
    log_info "Create a backup first:"
    log_info "  1. Open uBlock Origin settings"
    log_info "  2. Go to: Settings → About → Backup to file"
    log_info "  3. Save the file, then run this script with the path"
    exit 1
fi

log_info "Extracting filters from: $BACKUP_FILE"

# Extract static filters and custom filters using Python
python3 << EOF
import json
import sys

try:
    with open('$BACKUP_FILE', 'r') as f:
        data = json.load(f)
    
    # Extract static filters
    static_filters = data.get('staticFilterList', '')
    if static_filters:
        with open('$STATIC_FILTERS_FILE', 'w') as f:
            f.write(static_filters)
        print("✓ Static filters extracted to: $STATIC_FILTERS_FILE")
    else:
        print("⚠ No static filters found in backup")
    
    # Extract custom filters
    custom_filters = data.get('customFilters', '')
    if custom_filters:
        with open('$CUSTOM_FILTERS_FILE', 'w') as f:
            f.write(custom_filters)
        print("✓ Custom filters extracted to: $CUSTOM_FILTERS_FILE")
    else:
        print("⚠ No custom filters found in backup")
    
    # Show summary
    filter_lists = data.get('filterLists', {})
    if filter_lists:
        enabled_count = sum(1 for v in filter_lists.values() if v.get('disabled') != True)
        print(f"✓ Found {enabled_count} enabled filter lists")
    
except json.JSONDecodeError as e:
    print(f"Error: Invalid JSON in backup file: {e}", file=sys.stderr)
    sys.exit(1)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
EOF

if [[ $? -eq 0 ]]; then
    log_success "Filter extraction complete!"
    echo ""
    log_info "Files created:"
    [[ -f "$STATIC_FILTERS_FILE" ]] && log_info "  - $STATIC_FILTERS_FILE"
    [[ -f "$CUSTOM_FILTERS_FILE" ]] && log_info "  - $CUSTOM_FILTERS_FILE"
fi

