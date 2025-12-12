# Zen Browser Configuration

Automated setup and sync for Zen Browser settings, extensions, and keybindings.
Uses **Syncthing** for private extension data (passwords, wallet, filters).

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Machine                             │
│  ┌─────────────────┐    ┌─────────────────────────────────────┐ │
│  │  Zen Browser    │───▶│  export.sh                          │ │
│  │  Profile        │    │                                     │ │
│  └─────────────────┘    │  Public → ~/dotfiles/zen/config/    │ │
│                         │  Private → ~/Sync/zen-private/      │ │
│                         └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                    │
                    ┌───────────────┴───────────────┐
                    ▼                               ▼
            ┌──────────────┐                ┌──────────────┐
            │  Git (GitHub)│                │  Syncthing   │
            │  Public repo │                │  Private sync│
            └──────────────┘                └──────────────┘
                    │                               │
                    └───────────────┬───────────────┘
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                        New Machine                              │
│  ┌─────────────────────────────────────┐    ┌─────────────────┐ │
│  │  setup.sh                           │───▶│  Zen Browser    │ │
│  │                                     │    │  Profile        │ │
│  │  Clones dotfiles + imports from     │    └─────────────────┘ │
│  │  Syncthing with UUID remapping      │                        │
│  └─────────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────────┘
```

## Files

```
~/dotfiles/zen/              (Public - Git)
├── bootstrap.sh             # Automated setup for new machines
├── setup.sh                 # Install browser + apply all config
├── export.sh                # Export current settings
├── config/
│   ├── policies.json        # Extension auto-install list
│   ├── user.js              # Browser preferences
│   ├── zen-keyboard-shortcuts.json
│   ├── extension-preferences.json
│   ├── extension-settings.json
│   ├── zen-themes.json
│   └── chrome/              # Custom CSS

~/Sync/zen-private/          (Private - Syncthing)
├── uuid-mapping.json        # Extension ID to UUID mapping
├── last-export.txt          # Timestamp of last export
├── browser-extension-data/  # Extension local storage
└── storage/                 # Extension IndexedDB (uBlock, Vimium, etc.)
```

## Usage

### On a new machine (Automated - Recommended):

```bash
# Option 1: Fully automated (with Tailscale key + Syncthing API access)
# Get homeserver API key from: ~/appdata/syncthing/config/config.xml on tower
HOMESERVER_SYNC_URL="http://tower:8384" \
HOMESERVER_SYNC_APIKEY="your-api-key-here" \
curl -fsSL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/j4ck3/dotfiles/refs/heads/master/zen/bootstrap.sh?t=$(date +%s)" | bash -s -- "tskey-auth-XXXXX-XXXXX"

# Option 2: Via SSH (if you have SSH access to tower)
HOMESERVER_SSH="jacke@tower" \
curl -fsSL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/j4ck3/dotfiles/refs/heads/master/zen/bootstrap.sh?t=$(date +%s)" | bash -s -- "tskey-auth-XXXXX-XXXXX"

# Option 3: With Tailscale key only (manual Syncthing setup required)
curl -fsSL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/j4ck3/dotfiles/refs/heads/master/zen/bootstrap.sh?t=$(date +%s)" | bash -s -- "tskey-auth-XXXXX-XXXXX"

# Option 4: Manual Tailscale auth
sudo tailscale up
curl -fsSL -H "Cache-Control: no-cache" "https://raw.githubusercontent.com/j4ck3/dotfiles/refs/heads/master/zen/bootstrap.sh?t=$(date +%s)" | bash

# Launch browser - everything is configured!
```

**Get a Tailscale pre-auth key:** https://login.tailscale.com/admin/settings/keys

The bootstrap script will:

- ✅ Check prerequisites (Tailscale, Docker, yay)
- ✅ Clone dotfiles and compose repos
- ✅ Start Syncthing container
- ✅ Configure Syncthing via API (add homeserver, folders)
- ✅ Wait for sync to complete
- ✅ Install Zen Browser and apply all settings

**Note:** Your homeserver (tower) needs to accept the new device connection once in its Syncthing UI.

### On a new machine (Manual):

```bash
# 1. Clone your dotfiles
git clone https://github.com/j4ck3/dotfiles ~/dotfiles

# 2. Set up Syncthing and add the zen-private folder
#    (wait for it to sync from your homeserver)

# 3. Run setup
~/dotfiles/zen/setup.sh

# 4. Launch browser - everything is configured!
```

### After making changes in the browser:

```bash
# Just run export - everything is automatic
~/dotfiles/zen/export.sh

# Public config → auto-committed to git
# Private data → auto-synced via Syncthing
```

## What Gets Synced Where

| Data                   | Location            | How           |
| ---------------------- | ------------------- | ------------- |
| Extensions list        | Public (git)        | policies.json |
| Keyboard shortcuts     | Public (git)        | Automatic     |
| Browser preferences    | Public (git)        | user.js       |
| Zen themes/CSS         | Public (git)        | Automatic     |
| uBlock Origin filters  | Private (Syncthing) | Automatic     |
| Vimium-C keybindings   | Private (Syncthing) | Automatic     |
| MetaMask wallet        | Private (Syncthing) | Automatic     |
| Bitwarden data         | Private (Syncthing) | Automatic     |
| All extension settings | Private (Syncthing) | Automatic     |

## Setup Requirements

**For automated setup (bootstrap.sh):**

**No prerequisites needed!** The bootstrap script will automatically install:

- **yay** (AUR helper) - if not already installed
- **Docker** - if not already installed
- **Tailscale** - optional, will prompt to install/connect if needed

**The bootstrap script handles:**

- yay installation (from AUR)
- Docker installation and service setup
- Tailscale installation and connection (optional)
- Syncthing installation (via Docker Compose)
- Syncthing configuration (API-based, fully automated)
- Folder sharing setup
- Everything else!

**Manual setup requirements:**

1. **Tailscale** installed and connected on all machines
   - Both machines must be on the same Tailscale network
   - Homeserver (tower) must be accessible via Tailscale
2. **Syncthing** installed on all machines (via Docker Compose)
3. **Docker** installed on new machines
4. Shared folder `zen-private` between machines (configure manually)

## Extensions

Your 11 extensions auto-install via `policies.json`:

- uBlock Origin
- Dark Reader
- Vimium C
- Bitwarden Password Manager
- SponsorBlock
- Startpage Private Search (set as default search engine)
- Stylus
- I still don't care about cookies
- Enhancer for YouTube
- Floccus bookmarks sync
- MetaMask

## How UUID Remapping Works

Firefox assigns a unique UUID to each extension per-profile. Extension storage is keyed by this UUID.

When you run `setup.sh` on a new machine:

1. Extensions install with new UUIDs
2. Script reads old UUID mapping from Syncthing
3. Script reads new UUID mapping from new profile
4. Script copies storage directories, renaming UUIDs

This means your uBlock filters, Vimium keybindings, etc. "just work" on the new machine.

## Troubleshooting

### Extensions not installing

- Check `/usr/lib/zen-browser/distribution/policies.json` exists
- Restart browser completely

### Extension settings not restored

- Make sure Syncthing has finished syncing `~/Sync/zen-private/`
- Run `setup.sh` again after extensions are installed
- Check `~/Sync/zen-private/uuid-mapping.json` exists

### Syncthing not syncing

- Check Tailscale/VPN connection
- Verify folder is shared in Syncthing UI
- Check for conflicts in Syncthing
