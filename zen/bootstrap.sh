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

# Tailscale pre-auth key (optional - can be passed as env var or argument)
# Get one from: https://login.tailscale.com/admin/settings/keys
# Usage: TAILSCALE_AUTHKEY="tskey-..." ./bootstrap.sh
# Or: ./bootstrap.sh "tskey-..."
if [[ -n "${1:-}" ]] && [[ "${1}" == tskey-* ]]; then
    TAILSCALE_AUTHKEY="${1}"
fi
TAILSCALE_AUTHKEY="${TAILSCALE_AUTHKEY:-}"

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
    config=$(curl -s -H "$auth_header" "$api_url/config")
    
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
        local http_code
        http_code=$(curl -s -w "%{http_code}" -o /dev/null -X POST -H "$auth_header" -H "Content-Type: application/json" \
            -d "$device_json" "$api_url/config/devices")
        
        if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
            log_success "Added homeserver device"
            changes_made=true
        elif [[ "$http_code" -eq 400 || "$http_code" -eq 409 ]]; then
            # 400/409 usually means it already exists or invalid request
            log_info "Homeserver device may already exist (HTTP $http_code)"
            # Re-check config to confirm
            config=$(curl -s -H "$auth_header" "$api_url/config")
            if echo "$config" | grep -q "$HOMESERVER_DEVICE_ID"; then
                log_info "Homeserver device is configured"
            else
                log_warn "Device not found in config despite error - may need manual configuration"
            fi
        else
            log_warn "Failed to add homeserver device (HTTP $http_code)"
        fi
    else
        log_info "Homeserver device already configured"
    fi
    
    # Add folders
    for folder_config in "${SYNC_FOLDERS[@]}"; do
        local folder_id="${folder_config%%:*}"
        local folder_path="${folder_config##*:}"
        
        # Check if folder already exists
        if echo "$config" | grep -q "\"id\":\"$folder_id\""; then
            log_info "Folder '$folder_id' already configured"
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
        local http_code
        http_code=$(curl -s -w "%{http_code}" -o /dev/null -X POST -H "$auth_header" -H "Content-Type: application/json" \
            -d "$folder_json" "$api_url/config/folders")
        
        if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
            log_success "Added folder: $folder_id"
            changes_made=true
        elif [[ "$http_code" -eq 400 || "$http_code" -eq 409 ]]; then
            # 400/409 usually means it already exists or invalid request
            log_info "Folder '$folder_id' may already exist (HTTP $http_code)"
            # Re-check config to confirm
            config=$(curl -s -H "$auth_header" "$api_url/config")
            if echo "$config" | grep -q "\"id\":\"$folder_id\""; then
                log_info "Folder '$folder_id' is configured"
            else
                log_warn "Folder not found in config despite error - may need manual configuration"
            fi
        else
            log_warn "Failed to add folder '$folder_id' (HTTP $http_code)"
        fi
    done
    
    # Only restart if changes were made
    if [[ "$changes_made" == true ]]; then
        log_info "Restarting Syncthing to apply changes..."
        local http_code
        http_code=$(curl -s -w "%{http_code}" -o /dev/null -X POST -H "$auth_header" "$api_url/system/restart")
        if [[ "$http_code" -ge 200 && "$http_code" -lt 300 ]]; then
            sleep 5
            log_success "Syncthing configured and restarted!"
        else
            log_warn "Restart command returned HTTP $http_code, but continuing..."
            sleep 2
        fi
    else
        log_success "Syncthing already configured (no changes needed)"
    fi
}

wait_for_sync() {
    log_step "Step 5: Waiting for Syncthing to sync"
    
    # Check if already synced
    if [[ -f "$HOME/Sync/zen-private/uuid-mapping.json" ]]; then
        log_success "zen-private folder already synced (uuid-mapping.json exists)"
        return 0
    fi
    
    local api_key
    if ! api_key=$(get_api_key); then
        log_error "Could not get Syncthing API key for sync check"
        return 1
    fi
    
    if [[ -z "$api_key" ]]; then
        log_error "API key is empty"
        return 1
    fi
    
    local api_url="http://localhost:8384/rest"
    local auth_header="X-API-Key: $api_key"
    
    echo ""
    echo "Waiting for zen-private folder to sync..."
    echo "(This may take a moment on first sync)"
    echo ""
    
    # Wait for folder to be up to date
    local attempts=0
    local max_attempts=120  # 10 minutes max
    
    while [[ $attempts -lt $max_attempts ]]; do
        # Check folder status
        local status
        status=$(curl -s -H "$auth_header" "$api_url/db/status?folder=zen-private" 2>/dev/null)
        
        local state
        state=$(echo "$status" | grep -oP '(?<="state":")[^"]+' | head -1)
        
        if [[ "$state" == "idle" ]]; then
            # Check if uuid-mapping.json exists
            if [[ -f "$HOME/Sync/zen-private/uuid-mapping.json" ]]; then
                log_success "zen-private folder synced!"
                return 0
            fi
        fi
        
        # Show progress
        printf "\r  Status: %-20s (attempt %d/%d)" "$state" "$attempts" "$max_attempts"
        
        sleep 5
        ((attempts++))
    done
    
    echo ""
    log_warn "Sync taking longer than expected"
    
    if [[ -f "$HOME/Sync/zen-private/uuid-mapping.json" ]]; then
        log_success "But uuid-mapping.json exists, continuing..."
    else
        log_warn "uuid-mapping.json not found"
        echo ""
        echo "Check Syncthing UI at http://localhost:8384"
        echo "Make sure the homeserver has accepted this device."
        echo ""
        read -p "Press Enter to continue anyway, or Ctrl+C to abort..."
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
    
    check_prerequisites
    clone_repos
    start_syncthing
    configure_syncthing_api
    wait_for_sync
    run_setup
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                 Bootstrap Complete!                          ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "Launch Zen Browser and enjoy your fully configured setup!"
    echo ""
}

main "$@"

