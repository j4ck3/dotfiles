#!/bin/bash
#
# Zen Browser Bootstrap Script
# Run this on a fresh machine to set up everything automatically.
# Prerequisites: None (everything will be installed automatically)
# Optional: Tailscale (will prompt to install/connect if needed)
# Docker and yay will be installed automatically if not present
#
# Version: 2024-12-19 (auto-installs Docker and yay)
#

set -e

# Trap to show error location on exit
trap 'if [[ $? -ne 0 ]]; then echo ""; echo -e "${RED}[ERROR]${NC} Script failed at line $LINENO. Check the output above for details."; fi' ERR

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
GITHUB_USER="j4ck3"
DOTFILES_REPO="https://github.com/$GITHUB_USER/dotfiles"
COMPOSE_REPO="https://github.com/$GITHUB_USER/c"
HOMESERVER_NAME="tower"
HOMESERVER_DEVICE_ID="QARNKTH-UR6OW74-IFMPKOB-TQELLEZ-U4NPEEJ-UQXOX2U-2G3WE2O-YLEYPQB"
HOMESERVER_SYNC_URL_DEFAULT="http://10.0.0.24:8384"

# Tailscale pre-auth key (optional - can be passed as env var or argument)
# Get one from: https://login.tailscale.com/admin/settings/keys
# Usage: TAILSCALE_AUTHKEY="tskey-..." ./bootstrap.sh
# Or: ./bootstrap.sh "tskey-..."
if [[ -n "${1:-}" ]] && [[ "${1}" == tskey-* ]]; then
    TAILSCALE_AUTHKEY="${1}"
fi
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"

# Homeserver Syncthing API configuration (optional - for full automation)
# If provided, script will automatically configure homeserver side too
# 
# RECOMMENDED: Use SSH method (HOMESERVER_SSH) - most secure, no API key exposure
#   HOMESERVER_SSH="root@10.0.0.24" ./bootstrap.sh
#
# Alternative: Direct API access (less secure - exposes API key)
#   HOMESERVER_SYNC_URL="http://10.0.0.24:8384" HOMESERVER_SYNC_APIKEY="..." ./bootstrap.sh
HOMESERVER_SYNC_URL="${HOMESERVER_SYNC_URL:-}"
HOMESERVER_SYNC_APIKEY="${HOMESERVER_SYNC_APIKEY:-}"
HOMESERVER_SSH="${HOMESERVER_SSH:-}"

# Folders to sync (folder_id:container_path)
SYNC_FOLDERS=(
    "zen-private:/syncthing/zen-private"
)

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Docker command helper - uses sudo if needed
docker_cmd() {
    if docker info &> /dev/null; then
        docker "$@"
    else
        sudo docker "$@"
    fi
}

log_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

check_prerequisites() {
    log_step "Step 1: Checking prerequisites"
    
    # Check Tailscale (optional if on same network)
    TAILSCALE_NEEDED=true
    
    if command -v tailscale &> /dev/null; then
        # Check if Tailscale is connected
        if tailscale status &> /dev/null; then
            local tailscale_status
            tailscale_status=$(tailscale status 2>/dev/null | head -1)
            log_success "Tailscale connected: $tailscale_status"
            TAILSCALE_NEEDED=false
        elif [[ -n "$TAILSCALE_AUTHKEY" ]]; then
            log_info "Connecting to Tailscale using pre-auth key..."
            sudo tailscale up --authkey "$TAILSCALE_AUTHKEY"
            sleep 2
            if tailscale status &> /dev/null; then
                log_success "Tailscale connected"
                TAILSCALE_NEEDED=false
            fi
        else
            log_warn "Tailscale installed but not connected"
            log_info "If both machines are on the same local network, Tailscale is optional"
            log_info "Syncthing will use local network discovery"
            echo ""
            read -p "Connect to Tailscale anyway? [y/N] " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                log_info "Connecting to Tailscale..."
                echo "This may open a browser for authentication."
                sudo tailscale up
                sleep 2
                if tailscale status &> /dev/null; then
                    log_success "Tailscale connected"
                    TAILSCALE_NEEDED=false
                fi
            else
                log_info "Skipping Tailscale - using local network"
                TAILSCALE_NEEDED=false
            fi
        fi
    else
        log_info "Tailscale not installed"
        log_info "If both machines are on the same local network, Tailscale is optional"
        log_info "Syncthing will use local network discovery"
        echo ""
        read -p "Install Tailscale anyway? [y/N] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            log_info "Installing Tailscale..."
            curl -fsSL https://tailscale.com/install.sh | sh
            if [[ -n "$TAILSCALE_AUTHKEY" ]]; then
                sudo tailscale up --authkey "$TAILSCALE_AUTHKEY"
            else
                sudo tailscale up
            fi
            sleep 2
            if tailscale status &> /dev/null; then
                log_success "Tailscale connected"
                TAILSCALE_NEEDED=false
            fi
        else
            log_info "Skipping Tailscale - using local network"
            TAILSCALE_NEEDED=false
        fi
    fi
    
    # Check Docker
    if ! command -v docker &> /dev/null; then
        log_info "Docker not installed"
        echo ""
        read -t 10 -p "Install Docker? [Y/n] " -n 1 -r || REPLY="y"
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            log_info "Updating package database..."
            sudo pacman -Sy --noconfirm
            
            log_info "Installing Docker..."
            if sudo pacman -S --noconfirm docker docker-compose; then
                log_success "Docker packages installed"
            else
                log_error "Failed to install Docker packages"
                exit 1
            fi
            
            log_info "Enabling and starting Docker service..."
            sudo systemctl enable --now docker
            sleep 2  # Give service time to start
            
            # Verify Docker is working
            if sudo docker info &> /dev/null; then
                log_success "Docker service is running"
            else
                log_warn "Docker service may not be fully started yet"
            fi
            
            log_info "Adding user to docker group..."
            sudo usermod -aG docker "$USER"
            
            log_success "Docker installed and service started"
            log_warn "You may need to log out and back in for docker group changes to take effect"
            log_info "For now, using sudo for docker commands..."
        else
            log_error "Docker is required. Exiting."
            exit 1
        fi
    else
        log_success "Docker installed"
        
        # Check if Docker service is running
        if ! systemctl is-active --quiet docker 2>/dev/null; then
            log_info "Docker service not running, starting it..."
            sudo systemctl start docker
            sudo systemctl enable docker
            sleep 2
            log_success "Docker service started"
        fi
    fi
    
    # Check yay/paru
    if command -v yay &> /dev/null; then
        log_success "yay installed"
    elif command -v paru &> /dev/null; then
        log_success "paru installed"
    else
        log_info "No AUR helper (yay/paru) found"
        echo ""
        read -p "Install yay? [Y/n] " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            log_info "Installing yay..."
            
            # Install base-devel and git if not already installed
            if ! pacman -Q base-devel &> /dev/null; then
                log_info "Installing base-devel group..."
                sudo pacman -S --needed --noconfirm base-devel
            fi
            
            if ! pacman -Q git &> /dev/null; then
                log_info "Installing git..."
                sudo pacman -S --needed --noconfirm git
            fi
            
            # Clone and build yay
            log_info "Cloning yay from AUR..."
            cd /tmp
            rm -rf yay
            git clone https://aur.archlinux.org/yay.git
            cd yay
            makepkg -si --noconfirm
            
            # Verify installation
            if command -v yay &> /dev/null; then
                log_success "yay installed successfully"
            else
                log_error "yay installation failed"
                exit 1
            fi
        else
            log_error "AUR helper is required. Exiting."
            exit 1
        fi
    fi
}

clone_repos() {
    log_step "Step 2: Cloning repositories"
    
    # Clone dotfiles
    if [[ -d "$HOME/dotfiles" ]]; then
        log_info "Dotfiles already exists, pulling latest..."
        cd "$HOME/dotfiles" && git pull
    else
        log_info "Cloning dotfiles..."
        git clone "$DOTFILES_REPO" "$HOME/dotfiles"
    fi
    log_success "Dotfiles ready"
    
    # Clone compose repo
    if [[ -d "$HOME/c" ]]; then
        log_info "Compose repo already exists, pulling latest..."
        cd "$HOME/c" && git pull
    else
        log_info "Cloning compose repo..."
        git clone "$COMPOSE_REPO" "$HOME/c"
    fi
    log_success "Compose repo ready"
}

start_syncthing() {
    log_step "Step 3: Starting Syncthing"
    
    # Create directories
    mkdir -p ~/appdata/syncthing/config
    mkdir -p ~/Sync/zen-private
    
    # Check if Syncthing container is already running
    if docker_cmd ps | grep -q syncthing; then
        log_info "Syncthing container is already running"
    else
        # Start Syncthing
        cd "$HOME/c/z-syncthing"
        log_info "Starting Syncthing container..."
        docker_cmd compose up -d
        
        # Wait for container to be running
        log_info "Waiting for Syncthing container to start..."
        local attempts=0
        while ! docker_cmd ps | grep -q syncthing && [[ $attempts -lt 30 ]]; do
            sleep 1
            ((attempts++))
        done
        
        if ! docker_cmd ps | grep -q syncthing; then
            log_error "Syncthing container failed to start"
            docker_cmd logs syncthing 2>&1 | tail -20
            return 1
        fi
        
        log_success "Syncthing container started"
    fi
    
    log_success "Syncthing container is running"
    
    # Get device ID
    local device_id
    device_id=$(docker_cmd exec syncthing cat /config/config.xml 2>/dev/null | grep -oP '(?<=<device id=")[^"]+' | head -1) || true
    
    echo ""
    echo -e "${GREEN}Syncthing is running!${NC}"
    echo ""
    echo "Your Device ID: $device_id"
    echo ""
    echo "Web UI: http://localhost:8384"
    echo ""
}

get_api_key() {
    # Wait for Syncthing container to be ready and config.xml to be created
    log_info "Waiting for Syncthing to initialize config..."
    local attempts=0
    local max_attempts=60  # Wait up to 60 seconds
    
    while [[ $attempts -lt $max_attempts ]]; do
        # Try to get API key from container first (most reliable)
        local api_key
        api_key=$(docker_cmd exec syncthing cat /config/config.xml 2>/dev/null | grep -oP '(?<=<apikey>)[^<]+' | head -1) || true
        
        if [[ -n "$api_key" ]]; then
            echo "$api_key"
            return 0
        fi
        
        # Also try from host filesystem (in case it's mounted)
        local config_file="$HOME/appdata/syncthing/config/config.xml"
        if [[ -f "$config_file" ]]; then
            api_key=$(grep -oP '(?<=<apikey>)[^<]+' "$config_file" | head -1) || true
            if [[ -n "$api_key" ]]; then
                echo "$api_key"
                return 0
            fi
        fi
        
        # Check if container is running
        if ! docker_cmd ps | grep -q syncthing; then
            log_error "Syncthing container is not running!"
            docker_cmd logs syncthing 2>&1 | tail -20
            return 1
        fi
        
        sleep 1
        ((attempts++))
        
        if [[ $((attempts % 10)) -eq 0 ]]; then
            log_info "Still waiting for Syncthing config... (${attempts}/${max_attempts})"
        fi
    done
    
    log_error "Timeout waiting for Syncthing config.xml"
    log_info "Container logs:"
    docker_cmd logs syncthing 2>&1 | tail -30
    echo ""
    return 1
}

configure_syncthing_api() {
    log_step "Step 4: Configuring Syncthing via API"
    
    local api_key
    if ! api_key=$(get_api_key); then
        log_error "Could not get Syncthing API key"
        log_info "Troubleshooting:"
        log_info "1. Check if Syncthing container is running: docker ps"
        log_info "2. Check container logs: docker logs syncthing"
        log_info "3. Check if config directory exists: ls -la ~/appdata/syncthing/config/"
        log_info "4. Try accessing Syncthing UI: http://localhost:8384"
        return 1
    fi
    
    if [[ -z "$api_key" ]]; then
        log_error "API key is empty"
        return 1
    fi
    
    local api_url="http://localhost:8384/rest"
    local auth_header="X-API-Key: $api_key"
    
    log_info "Got API key, configuring Syncthing..."
    
    log_info "Using homeserver Device ID: ${HOMESERVER_DEVICE_ID:0:7}..."
    
    # Get current config
    log_info "Fetching current config..."
    local config
    config=$(curl -s -H "$auth_header" "$api_url/config" 2>&1)
    
    if [[ -z "$config" ]] || echo "$config" | grep -qi '"error"'; then
        log_error "Failed to fetch Syncthing config"
        if [[ -n "$config" ]]; then
            log_info "Response: ${config:0:300}"
        fi
        return 1
    fi
    
    local changes_made=false
    
    # Add homeserver device if not already added
    if ! echo "$config" | grep -q "$HOMESERVER_DEVICE_ID"; then
        log_info "Adding homeserver device: $HOMESERVER_NAME"
        
        local device_json=$(cat <<EOF
{
    "deviceID": "$HOMESERVER_DEVICE_ID",
    "name": "$HOMESERVER_NAME",
    "addresses": ["dynamic"],
    "compression": "metadata",
    "introducer": false,
    "paused": false
}
EOF
)
        local device_response
        device_response=$(curl -s -w "\n%{http_code}" -X POST -H "$auth_header" -H "Content-Type: application/json" \
            -d "$device_json" "$api_url/config/devices" 2>&1)
        local http_code
        http_code=$(echo "$device_response" | tail -1)
        local response_body
        response_body=$(echo "$device_response" | sed '$d')
        
        if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
            log_success "Added homeserver device"
            changes_made=true
        elif [[ "$http_code" -eq 400 || "$http_code" -eq 409 ]]; then
            # 400/409 usually means it already exists or invalid request
            log_info "Homeserver device may already exist (HTTP $http_code)"
            if [[ -n "$response_body" ]]; then
                log_info "Response: ${response_body:0:200}"
            fi
            # Re-check config to confirm
            config=$(curl -s -H "$auth_header" "$api_url/config")
            if echo "$config" | grep -q "$HOMESERVER_DEVICE_ID"; then
                log_success "Homeserver device is already configured"
            else
                log_error "Device not found in config despite HTTP $http_code"
                log_info "Full error response: $response_body"
                log_warn "This may indicate a configuration issue - check Syncthing logs"
            fi
        else
            log_error "Failed to add homeserver device (HTTP $http_code)"
            if [[ -n "$response_body" ]]; then
                log_info "Error response: ${response_body:0:200}"
            fi
        fi
    else
        log_info "Homeserver device already configured"
    fi
    
    # Add folders
    for folder_config in "${SYNC_FOLDERS[@]}"; do
        local folder_id="${folder_config%%:*}"
        local folder_path="${folder_config##*:}"
        
        # Check if folder already exists by label (Syncthing generates its own IDs)
        if echo "$config" | grep -q "\"label\":\"$folder_id\""; then
            log_info "Folder '$folder_id' already configured (by label)"
            continue
        fi
        
        # Also check by ID in case it was manually set
        if echo "$config" | grep -q "\"id\":\"$folder_id\""; then
            log_info "Folder '$folder_id' already configured (by ID)"
            continue
        fi
        
        log_info "Adding folder: $folder_id → $folder_path"
        
        local folder_json=$(cat <<EOF
{
    "id": "$folder_id",
    "label": "$folder_id",
    "path": "$folder_path",
    "type": "sendreceive",
    "devices": [
        {"deviceID": "$HOMESERVER_DEVICE_ID"}
    ],
    "rescanIntervalS": 3600,
    "fsWatcherEnabled": true,
    "fsWatcherDelayS": 10
}
EOF
)
        local folder_response
        folder_response=$(curl -s -w "\n%{http_code}" -X POST -H "$auth_header" -H "Content-Type: application/json" \
            -d "$folder_json" "$api_url/config/folders" 2>&1)
        local http_code
        http_code=$(echo "$folder_response" | tail -1)
        local response_body
        response_body=$(echo "$folder_response" | sed '$d')
        
        if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
            log_success "Added folder: $folder_id"
            changes_made=true
        elif [[ "$http_code" -eq 400 || "$http_code" -eq 409 ]]; then
            # 400/409 usually means it already exists or invalid request
            log_info "Folder '$folder_id' may already exist (HTTP $http_code)"
            if [[ -n "$response_body" ]]; then
                log_info "Response: ${response_body:0:200}"
            fi
            # Re-check config to confirm
            config=$(curl -s -H "$auth_header" "$api_url/config")
            if echo "$config" | grep -q "\"id\":\"$folder_id\""; then
                log_success "Folder '$folder_id' is already configured"
            else
                log_error "Folder not found in config despite HTTP $http_code"
                log_info "Full error response: $response_body"
                log_warn "This may indicate a configuration issue - check Syncthing logs"
            fi
        else
            log_error "Failed to add folder '$folder_id' (HTTP $http_code)"
            if [[ -n "$response_body" ]]; then
                log_info "Error response: ${response_body:0:200}"
            fi
        fi
    done
    
    # Get this device's ID for sharing with homeserver
    local this_device_id
    # Use the config we already fetched, or fetch again if needed
    if [[ -n "$config" ]]; then
        this_device_id=$(echo "$config" | grep -oP '(?<="myID":")[^"]+' | head -1)
    fi
    
    if [[ -z "$this_device_id" ]]; then
        # Try fetching again
        log_info "Fetching config again to get device ID..."
        local config_for_id
        config_for_id=$(curl -s -H "$auth_header" "$api_url/config" 2>&1)
        if [[ -n "$config_for_id" ]]; then
            this_device_id=$(echo "$config_for_id" | grep -oP '(?<="myID":")[^"]+' | head -1)
            # Also try alternative pattern
            if [[ -z "$this_device_id" ]]; then
                this_device_id=$(echo "$config_for_id" | grep -oP '(?<="myID" : ")[^"]+' | head -1)
            fi
            # Try with jq if available
            if [[ -z "$this_device_id" ]] && command -v jq &> /dev/null; then
                this_device_id=$(echo "$config_for_id" | jq -r '.myID' 2>/dev/null)
            fi
        fi
    fi
    
    if [[ -z "$this_device_id" ]]; then
        log_error "Could not retrieve this device's ID - cannot auto-configure homeserver"
        log_info "Tried multiple methods to extract device ID from config"
        if [[ -n "$config_for_id" ]]; then
            log_info "Config sample (first 500 chars): ${config_for_id:0:500}"
        fi
    fi
    
    if [[ -z "$this_device_id" ]]; then
        log_warn "Could not retrieve this device's ID - cannot auto-configure homeserver"
    else
        log_info "This device ID: ${this_device_id:0:7}..."
        
        # Try to automatically configure homeserver side if credentials provided
        if [[ -n "$HOMESERVER_SYNC_URL" ]] || [[ -n "$HOMESERVER_SSH" ]]; then
            if configure_homeserver_side "$this_device_id"; then
                log_success "Homeserver side configured successfully"
                
                # Verify configuration
                log_info "Verifying homeserver configuration..."
                verify_homeserver_config "$this_device_id" "$api_url" "$auth_header"
            else
                log_error "Failed to configure homeserver side - check errors above"
                log_warn "You may need to manually configure Syncthing on the homeserver"
            fi
        fi
    fi
    
    # Only restart if changes were made
    if [[ "$changes_made" == true ]]; then
        log_info "Restarting Syncthing to apply changes..."
        local restart_response
        restart_response=$(curl -s -w "\n%{http_code}" -X POST -H "$auth_header" "$api_url/system/restart" 2>&1)
        local restart_http_code
        restart_http_code=$(echo "$restart_response" | tail -1)
        
        if [[ "$restart_http_code" -ge 200 && "$restart_http_code" -lt 300 ]]; then
            sleep 5
            log_success "Syncthing configured and restarted!"
        else
            log_warn "Restart command returned HTTP $restart_http_code, but continuing..."
            sleep 2
        fi
    else
        log_success "Syncthing already configured (no changes needed)"
    fi
}

# Verify homeserver configuration was successful
verify_homeserver_config() {
    local device_id="$1"
    local api_url="$2"
    local auth_header="$3"
    
    log_info "Verifying configuration..."
    
    # Re-fetch config to verify
    local config
    config=$(curl -s -H "$auth_header" "$api_url/config" 2>&1)
    
    # Verify device was added
    if echo "$config" | grep -q "$HOMESERVER_DEVICE_ID"; then
        log_success "  ✓ Homeserver device is in config"
    else
        log_error "  ✗ Homeserver device NOT found in config"
        return 1
    fi
    
    # Verify folder exists
    if echo "$config" | grep -q "\"id\":\"zen-private\""; then
        log_success "  ✓ zen-private folder is in config"
    else
        log_error "  ✗ zen-private folder NOT found in config"
        return 1
    fi
    
    # Check device connection status
    local connections
    connections=$(curl -s -H "$auth_header" "$api_url/system/connections" 2>&1)
    if echo "$connections" | grep -q "$HOMESERVER_DEVICE_ID"; then
        local connected
        connected=$(echo "$connections" | grep -A 5 "$HOMESERVER_DEVICE_ID" | grep -oP '(?<="connected":)[^,]+' | head -1 || echo "false")
        if [[ "$connected" == "true" ]]; then
            log_success "  ✓ Homeserver device is connected"
        else
            log_warn "  ⚠ Homeserver device is not connected yet (may take a moment)"
        fi
    else
        log_warn "  ⚠ Homeserver device not in connections list yet"
    fi
    
    log_info "Configuration verification complete"
    
    # Show device ID and instructions (only if homeserver wasn't auto-configured)
    if [[ -z "$HOMESERVER_SYNC_URL" ]] && [[ -z "$HOMESERVER_SSH" ]]; then
        echo ""
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        log_info "IMPORTANT: Complete the Syncthing setup manually"
        log_info "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        log_info "This device ID: ${this_device_id:0:7}..."
        log_info "Full ID: $this_device_id"
        echo ""
        log_warn "You need to add this device on your homeserver (tower):"
        echo ""
        echo "1. Open Syncthing UI on homeserver: http://tower:8384"
        echo "2. Go to 'Actions' → 'Show ID' to see homeserver's device ID"
        echo "3. On THIS machine, go to: http://localhost:8384"
        echo "4. Click 'Add Device' and enter homeserver's device ID"
        echo "5. On homeserver, accept the new device when prompted"
        echo "6. On homeserver, share the 'zen-private' folder with this device"
        echo "7. On THIS machine, accept the folder share when prompted"
        echo ""
        log_info "Alternatively, for full automation, provide homeserver API access:"
        echo "  HOMESERVER_SYNC_URL='http://tower:8384' HOMESERVER_SYNC_APIKEY='...' ./bootstrap.sh"
        echo "  Or via SSH: HOMESERVER_SSH='jacke@tower' ./bootstrap.sh"
        echo ""
    fi
}

# Configure homeserver side automatically
configure_homeserver_side() {
    local this_device_id="$1"
    local this_device_name
    this_device_name=$(hostname)
    
    log_info "Attempting to auto-configure homeserver side..."
    
    # Method 1: Direct API access
    if [[ -n "$HOMESERVER_SYNC_URL" ]] && [[ -n "$HOMESERVER_SYNC_APIKEY" ]]; then
        log_info "Using direct API access to homeserver..."
        configure_homeserver_via_api "$this_device_id" "$this_device_name" "$HOMESERVER_SYNC_URL" "$HOMESERVER_SYNC_APIKEY"
        return $?
    fi
    
    # Method 2: SSH access
    if [[ -n "$HOMESERVER_SSH" ]]; then
        log_info "Using SSH to configure homeserver..."
        configure_homeserver_via_ssh "$this_device_id" "$this_device_name" "$HOMESERVER_SSH"
        return $?
    fi
    
    return 1
}

# Configure homeserver via direct API
configure_homeserver_via_api() {
    local device_id="$1"
    local device_name="$2"
    local api_url="$3"
    local api_key="$4"
    local auth_header="X-API-Key: $api_key"
    
    log_info "Connecting to homeserver Syncthing API: $api_url"
    log_info "Device to add: $device_name (${device_id:0:7}...)"
    
    # Test connection
    local test_response
    test_response=$(curl -s -w "\n%{http_code}" -H "$auth_header" "$api_url/rest/config" 2>&1)
    local http_code
    http_code=$(echo "$test_response" | tail -1)
    local response_body
    response_body=$(echo "$test_response" | sed '$d')
    
    if [[ "$http_code" != "200" ]]; then
        log_error "Cannot connect to homeserver Syncthing API (HTTP $http_code)"
        if [[ -n "$response_body" ]]; then
            log_info "Response: ${response_body:0:200}"
        fi
        return 1
    fi
    
    log_success "Connected to homeserver Syncthing API"
    
    # Get homeserver config
    local config
    config=$(curl -s -H "$auth_header" "$api_url/rest/config")
    
    if [[ -z "$config" ]]; then
        log_error "Failed to retrieve homeserver config"
        return 1
    fi
    
    # Add this device to homeserver
    if ! echo "$config" | grep -q "$device_id"; then
        log_info "Adding this device to homeserver: $device_name (${device_id:0:7}...)"
        
        local device_json=$(cat <<EOF
{
    "deviceID": "$device_id",
    "name": "$device_name",
    "addresses": ["dynamic"],
    "compression": "metadata",
    "introducer": false,
    "paused": false
}
EOF
)
        local add_response
        add_response=$(curl -s -w "\n%{http_code}" -X POST -H "$auth_header" -H "Content-Type: application/json" \
            -d "$device_json" "$api_url/rest/config/devices" 2>&1)
        local add_http_code
        add_http_code=$(echo "$add_response" | tail -1)
        local add_body
        add_body=$(echo "$add_response" | sed '$d')
        
        if [[ "$add_http_code" -ge 200 && "$add_http_code" -lt 300 ]]; then
            log_success "Added this device to homeserver"
        else
            log_error "Failed to add device to homeserver (HTTP $add_http_code)"
            if [[ -n "$add_body" ]]; then
                log_info "Error response: ${add_body:0:200}"
            fi
            return 1
        fi
    else
        log_info "Device already exists on homeserver"
    fi
    
    # Share zen-private folder with this device
    log_info "Sharing zen-private folder with this device..."
    
    # First, get all folders and find zen-private by label (folder ID might be different)
    log_info "Finding zen-private folder on homeserver..."
    local all_folders
    all_folders=$(curl -s -H "$auth_header" "$api_url/rest/config/folders" 2>&1)
    local folder_id
    folder_id=$(echo "$all_folders" | python3 -c "import sys, json; folders=json.load(sys.stdin); [print(f['id']) for f in folders if f.get('label') == 'zen-private']" 2>/dev/null | head -1)
    
    if [[ -z "$folder_id" ]]; then
        log_error "zen-private folder not found on homeserver"
        log_info "Available folders on homeserver:"
        echo "$all_folders" | python3 -c "import sys, json; folders=json.load(sys.stdin); [print(f\"  - {f.get('label', 'N/A')} (ID: {f.get('id', 'N/A')})\") for f in folders]" 2>/dev/null || echo "  (Could not parse folder list)"
        return 1
    fi
    
    log_info "Found zen-private folder with ID: $folder_id"
    
    # Get folder config using the actual folder ID
    local folder_response
    folder_response=$(curl -s -w "\n%{http_code}" -H "$auth_header" "$api_url/rest/config/folders/$folder_id" 2>&1)
    local folder_http_code
    folder_http_code=$(echo "$folder_response" | tail -1)
    local folder_config
    folder_config=$(echo "$folder_response" | sed '$d')
    
    if [[ "$folder_http_code" != "200" ]] || [[ -z "$folder_config" ]] || echo "$folder_config" | grep -q '"error"'; then
        log_error "Failed to get zen-private folder config (HTTP $folder_http_code)"
        if [[ -n "$folder_config" ]]; then
            log_info "Response: ${folder_config:0:200}"
        fi
        return 1
    fi
    
    log_success "Found zen-private folder on homeserver"
    
    # Check if device is already in folder's device list
    if echo "$folder_config" | grep -q "$device_id"; then
        log_info "Folder already shared with this device"
        return 0
    fi
    
    # Use Python to properly update JSON (more reliable than sed)
    log_info "Updating folder configuration to include this device..."
    local updated_config
    updated_config=$(python3 << PYEOF
import json
import sys

try:
    folder_config_str = '''$folder_config'''
    device_id = '$device_id'
    config = json.loads(folder_config_str)
    
    # Add device to devices list if not present
    device_exists = False
    for dev in config.get('devices', []):
        if dev.get('deviceID') == device_id:
            device_exists = True
            break
    
    if not device_exists:
        config.setdefault('devices', []).append({'deviceID': device_id})
        print(json.dumps(config))
    else:
        print(folder_config_str)
except Exception as e:
    print(f"Error: {e}", file=sys.stderr)
    sys.exit(1)
PYEOF
)
    
    if [[ -z "$updated_config" ]]; then
        log_error "Failed to update folder configuration (Python error)"
        return 1
    fi
    
    local share_response
    share_response=$(curl -s -w "\n%{http_code}" -X PUT -H "$auth_header" -H "Content-Type: application/json" \
        -d "$updated_config" "$api_url/rest/config/folders/$folder_id" 2>&1)
    local share_http_code
    share_http_code=$(echo "$share_response" | tail -1)
    local share_body
    share_body=$(echo "$share_response" | sed '$d')
    
    if [[ "$share_http_code" -ge 200 && "$share_http_code" -lt 300 ]]; then
        log_success "Shared zen-private folder with this device on homeserver"
        return 0
    else
        log_error "Failed to share folder (HTTP $share_http_code)"
        if [[ -n "$share_body" ]]; then
            log_info "Error response: ${share_body:0:200}"
        fi
        return 1
    fi
}

# Configure homeserver via SSH
configure_homeserver_via_ssh() {
    local device_id="$1"
    local device_name="$2"
    local ssh_target="$3"
    
    log_info "Connecting to homeserver via SSH: $ssh_target"
    
    # Test SSH connection first
    if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "$ssh_target" "echo 'SSH connection test'" > /dev/null 2>&1; then
        log_error "Cannot connect to homeserver via SSH: $ssh_target"
        log_info "Make sure SSH key authentication is set up: ssh-copy-id $ssh_target"
        return 1
    fi
    log_success "SSH connection successful"
    
    # Get homeserver Syncthing API key via SSH
    # Try multiple possible paths for Syncthing config
    log_info "Retrieving Syncthing API key from homeserver..."
    local api_key
    
    # First, try to find the config file dynamically
    log_info "  Searching for Syncthing config file..."
    local config_file
    config_file=$(ssh "$ssh_target" "find ~ /root /home -name 'config.xml' -path '*/syncthing/config/config.xml' 2>/dev/null | head -1" 2>/dev/null)
    
    if [[ -n "$config_file" ]]; then
        log_info "  Found config file at: $config_file"
        api_key=$(ssh "$ssh_target" "grep -oP '(?<=<apikey>)[^<]+' '$config_file' 2>/dev/null" 2>/dev/null)
    fi
    
    # Fallback to common paths if dynamic search didn't work
    if [[ -z "$api_key" ]]; then
        local config_paths=(
            "~/appdata/syncthing/config/config.xml"
            "/root/appdata/syncthing/config/config.xml"
            "/home/jacke/appdata/syncthing/config/config.xml"
        )
        
        # Extract username from SSH target if possible
        local ssh_user
        ssh_user=$(echo "$ssh_target" | cut -d'@' -f1)
        if [[ -n "$ssh_user" ]] && [[ "$ssh_user" != "$ssh_target" ]]; then
            config_paths+=("/home/$ssh_user/appdata/syncthing/config/config.xml")
        fi
        
        for path in "${config_paths[@]}"; do
            log_info "  Trying path: $path"
            api_key=$(ssh "$ssh_target" "grep -oP '(?<=<apikey>)[^<]+' $path 2>/dev/null" 2>/dev/null)
            if [[ -n "$api_key" ]]; then
                log_success "  Found API key at: $path"
                break
            fi
        done
    fi
    
    if [[ -z "$api_key" ]]; then
        log_error "Could not get homeserver Syncthing API key via SSH"
        log_info "Searched for config.xml in common locations"
        log_info "Please check if Syncthing is installed and configured on the homeserver"
        log_info "You can manually find the path: ssh $ssh_target 'find ~ -name config.xml -path \"*/syncthing/config/config.xml\"'"
        return 1
    fi
    
    log_info "API key retrieved successfully (length: ${#api_key} chars)"
    
    # Get homeserver Syncthing URL (usually localhost from SSH perspective)
    local api_url="http://localhost:8384/rest"
    local tunnel_port=8385
    
    # Use API method with SSH tunnel
    log_info "Creating SSH tunnel: localhost:$tunnel_port -> $ssh_target:8384"
    
    # Check if tunnel port is already in use
    if lsof -i :$tunnel_port > /dev/null 2>&1; then
        log_warn "Port $tunnel_port is already in use, trying to clean up..."
        pkill -f "ssh.*$tunnel_port:localhost:8384.*$ssh_target" 2>/dev/null || true
        sleep 1
    fi
    
    # Create SSH tunnel
    if ! ssh -f -N -o ExitOnForwardFailure=yes -L $tunnel_port:localhost:8384 "$ssh_target" 2>&1; then
        log_error "Failed to create SSH tunnel"
        return 1
    fi
    
    # Wait for tunnel to be ready
    sleep 2
    
    # Verify tunnel is working
    if ! curl -s -f "http://localhost:$tunnel_port/rest/config" > /dev/null 2>&1; then
        log_error "SSH tunnel created but cannot reach Syncthing API"
        pkill -f "ssh.*$tunnel_port:localhost:8384.*$ssh_target" 2>/dev/null || true
        return 1
    fi
    
    log_success "SSH tunnel established and verified"
    
    # Configure via API through tunnel
    configure_homeserver_via_api "$device_id" "$device_name" "http://localhost:$tunnel_port" "$api_key"
    local result=$?
    
    # Close tunnel
    log_info "Closing SSH tunnel..."
    pkill -f "ssh.*$tunnel_port:localhost:8384.*$ssh_target" 2>/dev/null || true
    
    return $result
}

wait_for_sync() {
    log_step "Step 5: Waiting for Syncthing to sync"
    
    # Check if already synced
    if [[ -f "$HOME/Sync/zen-private/uuid-mapping.json" ]]; then
        log_success "zen-private folder already synced (uuid-mapping.json exists)"
        return 0
    fi
    
    log_info "Getting Syncthing API key..."
    local api_key
    if ! api_key=$(get_api_key); then
        log_error "Could not get Syncthing API key for sync check"
        log_info "This might be a temporary issue. You can:"
        log_info "1. Check Syncthing UI: http://localhost:8384"
        log_info "2. Wait a bit and run the script again"
        log_info "3. Check container logs: docker logs syncthing"
        return 1
    fi
    
    if [[ -z "$api_key" ]]; then
        log_error "API key is empty"
        return 1
    fi
    
    log_info "API key retrieved, checking sync status..."
    local api_url="http://localhost:8384/rest"
    local auth_header="X-API-Key: $api_key"
    
    # First, check if folder exists in config (by label or by checking if files exist)
    log_info "Checking if zen-private folder is configured..."
    
    # Check if the sync directory and uuid-mapping.json exist (most reliable)
    if [[ -f "$HOME/Sync/zen-private/uuid-mapping.json" ]]; then
        log_success "zen-private folder is synced (uuid-mapping.json exists)"
        return 0
    fi
    
    # Also check via API
    local config
    config=$(curl -s -H "$auth_header" "$api_url/config" 2>/dev/null) || true
    local folder_found=false
    
    # Check by label "zen-private" (folder might have different ID)
    if echo "$config" | grep -q "\"label\":\"zen-private\""; then
        folder_found=true
    fi
    
    # Also check if folder directory exists
    if [[ -d "$HOME/Sync/zen-private" ]]; then
        folder_found=true
    fi
    
    if [[ "$folder_found" == false ]]; then
        log_warn "zen-private folder not found in Syncthing config or filesystem"
        log_info "The folder may not have been added correctly."
        log_info "Check Syncthing UI: http://localhost:8384"
        log_warn "You may need to manually add the folder or accept it from the homeserver"
        return 1
    fi
    log_success "zen-private folder is configured"
    
    # Check if folder is paused or has errors (find folder ID by label first)
    local folder_id
    folder_id=$(echo "$config" | grep -B 5 '"label":"zen-private"' | grep -oP '(?<="id":")[^"]+' | head -1) || true
    
    if [[ -n "$folder_id" ]]; then
        local folder_status
        folder_status=$(curl -s -H "$auth_header" "$api_url/db/status?folder=$folder_id" 2>/dev/null) || true
        if echo "$folder_status" | grep -q '"invalid"'; then
            log_warn "Folder appears to be invalid or not properly shared"
            log_info "Make sure the homeserver has shared this folder with this device"
        fi
    fi
    
    # Check device connection status
    log_info "Checking device connection status..."
    local connections
    connections=$(curl -s -H "$auth_header" "$api_url/system/connections" 2>/dev/null) || true
    local homeserver_connected=false
    
    if [[ -z "$connections" ]]; then
        log_warn "Could not retrieve connection status"
    elif echo "$connections" | grep -q "$HOMESERVER_DEVICE_ID"; then
        # Check if connected
        local connected
        connected=$(echo "$connections" | grep -A 10 "$HOMESERVER_DEVICE_ID" | grep -oP '(?<="connected":)[^,}]+' | head -1 || echo "false")
        local paused
        paused=$(echo "$connections" | grep -A 10 "$HOMESERVER_DEVICE_ID" | grep -oP '(?<="paused":)[^,}]+' | head -1 || echo "false")
        
        if [[ "$connected" == "true" ]]; then
            homeserver_connected=true
            log_success "Homeserver ($HOMESERVER_NAME) is connected"
            if [[ "$paused" == "true" ]]; then
                log_warn "  ⚠ Homeserver device is paused"
            fi
        else
            log_warn "Homeserver ($HOMESERVER_NAME) is not connected"
            log_info "  Connection status: connected=$connected, paused=$paused"
            log_info "  Make sure both devices are on the same network/Tailscale"
            log_info "  Check firewall rules (Syncthing uses ports 22000 and 8384)"
        fi
    else
        log_warn "Homeserver device not found in connections list"
        log_info "  This might mean the device hasn't been added yet or Syncthing hasn't discovered it"
    fi
    
    echo ""
    echo "Waiting for zen-private folder to sync..."
    echo "(This may take a moment on first sync)"
    if [[ "$homeserver_connected" == "false" ]]; then
        echo -e "${YELLOW}Note: Homeserver appears disconnected - sync may not work${NC}"
    fi
    echo ""
    
    # Wait for folder to be up to date
    local attempts=0
    local max_attempts=120  # 10 minutes max
    local last_state=""
    local last_progress=""
    
            # Find folder ID by label
            local folder_id
            folder_id=$(echo "$config" | grep -B 5 '"label":"zen-private"' | grep -oP '(?<="id":")[^"]+' | head -1) || true
            
            if [[ -z "$folder_id" ]]; then
                log_warn "Could not find zen-private folder ID, checking by file existence only"
            fi
            
            while [[ $attempts -lt $max_attempts ]]; do
                # Check folder status (allow curl to fail without exiting)
                local status
                if [[ -n "$folder_id" ]]; then
                    status=$(curl -s -H "$auth_header" "$api_url/db/status?folder=$folder_id" 2>/dev/null) || true
                else
                    status=""
                fi
        
        local state="unknown"
        local progress=""
        local need_items=0
        local global_bytes=0
        local local_bytes=0
        
        if [[ -n "$status" ]]; then
            # Extract state, allow grep to fail
            state=$(echo "$status" | grep -oP '(?<="state":")[^"]+' | head -1 || echo "unknown")
            
            # Extract progress info
            need_items=$(echo "$status" | grep -oP '(?<="needItems":)[0-9]+' | head -1 || echo "0")
            global_bytes=$(echo "$status" | grep -oP '(?<="globalBytes":)[0-9]+' | head -1 || echo "0")
            local_bytes=$(echo "$status" | grep -oP '(?<="localBytes":)[0-9]+' | head -1 || echo "0")
            
            if [[ "$need_items" -gt 0 ]]; then
                progress=" (need $need_items items)"
            elif [[ "$global_bytes" -gt 0 ]]; then
                local percent=0
                if [[ "$global_bytes" -gt 0 ]]; then
                    percent=$((local_bytes * 100 / global_bytes))
                fi
                progress=" ($percent% - ${local_bytes}/${global_bytes} bytes)"
            fi
        fi
        
        # Show detailed status every 10 attempts or when state changes
        if [[ "$attempts" -eq 0 ]] || [[ "$attempts" -eq 10 ]] || [[ "$((attempts % 20))" -eq 0 ]] || [[ "$state" != "$last_state" ]]; then
            echo ""
            log_info "Status: $state$progress (attempt $attempts/$max_attempts)"
            if [[ -d "$HOME/Sync/zen-private" ]]; then
                local file_count
                file_count=$(find "$HOME/Sync/zen-private" -type f 2>/dev/null | wc -l || echo "0")
                log_info "Files in local folder: $file_count"
            fi
            last_state="$state"
        fi
        
        if [[ "$state" == "idle" ]]; then
            # Check if uuid-mapping.json exists
            if [[ -f "$HOME/Sync/zen-private/uuid-mapping.json" ]]; then
                echo ""  # New line after progress
                log_success "zen-private folder synced!"
                return 0
            elif [[ "$need_items" -eq 0 ]]; then
                # State is idle and no items needed, but file doesn't exist
                echo ""
                log_warn "Folder state is 'idle' but uuid-mapping.json not found"
                log_info "This might mean the folder is empty on the homeserver"
                log_info "Check if the homeserver has the file and has shared the folder"
                break
            fi
        fi
        
        # Show progress on same line
        if [[ "$((attempts % 5))" -eq 0 ]]; then
            printf "\r  Status: %-20s%s (attempt %d/%d)" "$state" "$progress" "$attempts" "$max_attempts" || true
        fi
        
        sleep 5
        ((attempts++))
    done
    
    echo ""
    log_warn "Sync timeout or incomplete"
    
    if [[ -f "$HOME/Sync/zen-private/uuid-mapping.json" ]]; then
        log_success "But uuid-mapping.json exists, continuing..."
    else
        log_warn "uuid-mapping.json not found after waiting"
        echo ""
        echo "Troubleshooting steps:"
        echo "1. Check Syncthing UI on this machine: http://localhost:8384"
        echo "2. Check Syncthing UI on homeserver (tower)"
        echo "3. Verify both devices are connected:"
        echo "   - Check 'Remote Devices' in Syncthing UI"
        echo "   - Make sure 'tower' device shows as 'Connected'"
        echo "4. Verify folder sharing:"
        echo "   - On homeserver: Check that 'zen-private' folder is shared with this device"
        echo "   - On this machine: Check that 'zen-private' folder shows the homeserver"
        echo "5. Check folder status:"
        echo "   - Look for any error messages in Syncthing UI"
        echo "   - Check if folder is 'Paused' or has conflicts"
        echo "6. Check network connectivity:"
        echo "   - If using Tailscale: tailscale ping tower"
        echo "   - If local network: ping the homeserver IP"
        echo ""
        echo "You can continue and run setup.sh manually later, or fix the sync issue and re-run bootstrap.sh"
        echo ""
        if [[ -t 0 ]]; then
            # Only prompt if stdin is a terminal
            read -p "Press Enter to continue anyway, or Ctrl+C to abort..." || true
        else
            log_warn "Non-interactive mode - continuing anyway..."
        fi
    fi
}

run_setup() {
    log_step "Step 6: Running Zen Browser setup"
    
    # Check if Zen Browser is already installed and configured
    if command -v zen &> /dev/null && [[ -d "$HOME/.zen" ]] && [[ -f "$HOME/Sync/zen-private/uuid-mapping.json" ]]; then
        log_info "Zen Browser appears to be already installed and configured"
        echo ""
        read -t 5 -p "Run setup anyway? [y/N] " -n 1 -r || REPLY="n"
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "Skipping setup (Zen Browser already configured)"
            return 0
        fi
    fi
    
    cd "$HOME/dotfiles/zen"
    ./setup.sh
}

# Main
main() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║           Zen Browser Bootstrap Script                       ║${NC}"
    echo -e "${BLUE}║       Fresh Machine → Full Browser Setup                     ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if ! check_prerequisites; then
        log_error "Prerequisites check failed"
        exit 1
    fi
    
    if ! clone_repos; then
        log_error "Failed to clone repositories"
        exit 1
    fi
    
    if ! start_syncthing; then
        log_error "Failed to start Syncthing"
        exit 1
    fi
    
    if ! configure_syncthing_api; then
        log_error "Failed to configure Syncthing"
        exit 1
    fi
    
    # wait_for_sync can fail but we might want to continue anyway
    if ! wait_for_sync; then
        log_warn "Sync check failed or incomplete, but continuing..."
        if [[ ! -f "$HOME/Sync/zen-private/uuid-mapping.json" ]]; then
            log_warn "uuid-mapping.json not found - setup may not work correctly"
            log_info "You may need to wait for sync to complete and run setup.sh manually"
        fi
    fi
    
    if ! run_setup; then
        log_error "Setup failed"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 Bootstrap Complete!                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Launch Zen Browser and enjoy your fully configured setup!"
    echo ""
}

main "$@"

