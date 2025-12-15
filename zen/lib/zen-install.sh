#!/bin/bash
#
# Zen Browser installation functions
# Handles AUR helper checks and browser installation
#

# Check for and install yay if needed
check_aur_helper() {
    if command -v yay &> /dev/null; then
        log_success "yay is installed"
        AUR_HELPER="yay"
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

