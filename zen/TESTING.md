# Testing the Bootstrap Script

## Option 1: VM on Unraid (Recommended)

### Create a test VM:

1. **Create a new Arch Linux VM in Unraid:**
   - VM Manager → Add VM
   - Template: Arch Linux
   - Allocate: 2-4GB RAM, 20GB disk
   - Network: Bridge (so it can reach Tailscale)

2. **Install Arch Linux:**
   ```bash
   # Boot from ISO, then:
   # Follow standard Arch install guide
   # Install base system, network, etc.
   ```

3. **Install prerequisites (optional):**
   
   **Note:** The bootstrap script will automatically install yay, Docker, and optionally Tailscale if they're not present. You can skip this step to test the full automated installation, or install them manually if you prefer:
   
   ```bash
   # Install Tailscale (optional - script will prompt)
   curl -fsSL https://tailscale.com/install.sh | sh
   
   # Install Docker (optional - script will install automatically)
   pacman -S docker
   systemctl enable --now docker
   
   # Install yay (optional - script will install automatically)
   git clone https://aur.archlinux.org/yay.git
   cd yay && makepkg -si
   ```

4. **Test the bootstrap script:**
   ```bash
   # With pre-auth key (recommended for testing)
   curl -fsSL https://raw.githubusercontent.com/j4ck3/dotfiles/refs/heads/master/zen/bootstrap.sh | bash -s -- "YOUR-TAILSCALE-AUTH-KEY"
   ```

5. **Verify everything works:**
   - Check Syncthing UI: http://localhost:8384
   - Check if zen-private synced
   - Launch Zen Browser
   - Verify extensions installed
   - Check if settings are applied

### Cleanup:
   - Delete the VM when done
   - Or keep it for future testing

## Option 2: Docker Container (Limited)

**Note:** This won't work well because:
- Can't install system packages (yay, zen-browser)
- No GUI for browser testing
- Limited system access

## Option 3: Cloud VM (Temporary)

1. **Spin up a cheap VPS:**
   - DigitalOcean, Linode, etc.
   - $5/month droplet
   - Install Arch Linux

2. **Test the script**

3. **Delete when done**

## Option 4: Physical Test Machine

If you have a spare laptop/PC:
- Install Arch Linux
- Test the full script
- Most realistic test environment

## Testing Checklist

- [ ] Tailscale connects automatically
- [ ] Syncthing starts and configures
- [ ] Homeserver device is added
- [ ] Folders are created and shared
- [ ] zen-private syncs successfully
- [ ] Zen Browser installs
- [ ] Extensions auto-install
- [ ] Settings are applied
- [ ] Extension storage is restored (UUID remapping works)

## Quick Test (Partial)

If you just want to test the Syncthing setup part:

```bash
# On a test machine, just run the Syncthing parts:
git clone https://github.com/j4ck3/c ~/c
cd ~/c/z-syncthing
mkdir -p ~/appdata/syncthing/config ~/Sync/zen-private
docker compose up -d

# Then manually test the API calls from bootstrap.sh
```

## Debugging

If something fails:

1. **Check logs:**
   ```bash
   docker logs syncthing
   tailscale status
   ```

2. **Test individual components:**
   ```bash
   # Test Tailscale
   tailscale ping tower
   
   # Test Syncthing API
   API_KEY=$(grep -oP '(?<=<apikey>)[^<]+' ~/appdata/syncthing/config/config.xml)
   curl -H "X-API-Key: $API_KEY" http://localhost:8384/rest/config
   ```

3. **Run script with debug:**
   ```bash
   bash -x bootstrap.sh
   ```

