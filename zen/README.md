# Zen Browser Configuration

Automated setup and sync for Zen Browser settings, extensions, and keybindings.
Uses **Git** for all configuration - simple, version-controlled, and shareable.

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Your Machine                             │
│  ┌─────────────────┐    ┌─────────────────────────────────────┐ │
│  │  Zen Browser    │───▶│  export.sh                          │ │
│  │  Profile        │    │                                     │ │
│  └─────────────────┘    │  → ~/dotfiles/zen/config/          │ │
│                         └─────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
                            ┌──────────────┐
                            │  Git (GitHub)│
                            │  Public repo │
                            └──────────────┘
                                    │
                                    ▼
┌─────────────────────────────────────────────────────────────────┐
│                        New Machine                              │
│  ┌─────────────────────────────────────┐    ┌─────────────────┐ │
│  │  setup.sh                           │───▶│  Zen Browser    │ │
│  │                                     │    │  Profile        │ │
│  │  Clones dotfiles + applies config   │    └─────────────────┘ │
│  └─────────────────────────────────────┘                        │
└─────────────────────────────────────────────────────────────────┘
```

## File Structure

```
~/dotfiles/zen/
├── bootstrap.sh              # Simple entry point: clone repo + install browser
├── setup.sh                  # Main setup script (applies all config)
├── export.sh                 # Export current settings
├── lib/                      # Modular functions (DRY/SOLID principles)
│   ├── common.sh             # Shared utilities (logging, colors, config paths)
│   ├── zen-install.sh        # Zen Browser installation logic
│   ├── zen-profile.sh        # Profile detection and creation
│   ├── config-deploy.sh      # Configuration deployment functions
│   └── ublock-export.sh      # uBlock Origin filter export
└── config/                   # Git-controlled configuration
    ├── policies.json         # Extension auto-install list
    ├── user.js               # Browser preferences
    ├── zen-keyboard-shortcuts.json
    ├── extension-preferences.json
    ├── extension-settings.json
    ├── zen-themes.json
    ├── chrome/               # Custom CSS
    └── ublock-filters-backup.json  # uBlock Origin filter backup
```

## Usage

### On a new machine (Quick Start - Recommended):

```bash
# One-liner: Clone repo + install browser + apply config
curl -fsSL https://raw.githubusercontent.com/j4ck3/dotfiles/master/zen/bootstrap.sh | bash && ~/dotfiles/zen/setup.sh

# Or step by step:
# 1. Bootstrap (clones repo + installs browser)
curl -fsSL https://raw.githubusercontent.com/j4ck3/dotfiles/master/zen/bootstrap.sh | bash

# 2. Setup (applies configuration)
~/dotfiles/zen/setup.sh

# 3. Launch browser - extensions will auto-install!

# 4. Import uBlock filters manually:
#    - Open uBlock Origin settings
#    - Go to: Settings → About → Restore from file
#    - Select: ~/dotfiles/zen/config/ublock-filters-backup.json
```

### On a new machine (Manual):

```bash
# 1. Clone your dotfiles
git clone https://github.com/j4ck3/dotfiles ~/dotfiles

# 2. Run bootstrap (installs browser)
~/dotfiles/zen/bootstrap.sh

# 3. Run setup (applies configuration)
~/dotfiles/zen/setup.sh

# 4. Launch browser - extensions will auto-install!

# 5. Import uBlock filters manually:
#    - Open uBlock Origin settings
#    - Go to: Settings → About → Restore from file
#    - Select: ~/dotfiles/zen/config/ublock-filters-backup.json
```

### After making changes in the browser:

```bash
# Export all configuration
~/dotfiles/zen/export.sh

# Changes are auto-committed to git
# Push to GitHub: git push
```

## What Gets Synced

| Data                  | Location     | How           |
| --------------------- | ------------ | ------------- |
| Extensions list       | Git (public) | policies.json |
| Keyboard shortcuts    | Git (public) | Automatic     |
| Browser preferences   | Git (public) | user.js       |
| Zen themes/CSS        | Git (public) | Automatic     |
| Extension preferences | Git (public) | Automatic     |
| Extension settings    | Git (public) | Automatic     |
| uBlock Origin filters | Git (public) | Manual export |

**Note:** Extension settings (like uBlock filters) are exported to git-controlled files. You can import them manually after setup. Sensitive data (passwords, wallets) should be handled separately and not committed to git.

## Setup Requirements

**Prerequisites:**

- **yay** or **paru** (AUR helper) - required for installing Zen Browser
- **Git** - for cloning the dotfiles repository

**The bootstrap script will:**

- Check for yay/paru (exits with instructions if not found)
- Clone dotfiles repository (if not already present)
- Install Zen Browser from AUR

**The setup script will:**

- Install Zen Browser (if not already installed)
- Deploy extension policies (auto-install extensions)
- Create browser profile
- Apply all configuration files

## Extensions

Your extensions auto-install via `policies.json`:

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

## Module Architecture

The scripts follow **DRY** and **SOLID** principles:

- **lib/common.sh** - Shared utilities (logging, colors, config paths)
- **lib/zen-install.sh** - Browser installation logic
- **lib/zen-profile.sh** - Profile management
- **lib/config-deploy.sh** - Configuration deployment
- **lib/ublock-export.sh** - uBlock filter export

Each module has a single responsibility and can be tested independently.

## uBlock Origin Filter Export

uBlock Origin filters are exported to `config/ublock-filters-backup.json` in a format compatible with uBlock's import feature.

**To export:**

```bash
~/dotfiles/zen/export.sh
```

**To import on a new machine:**

1. Install uBlock Origin (auto-installed via policies.json)
2. Open uBlock Origin settings
3. Go to: Settings → About → Restore from file
4. Select: `~/dotfiles/zen/config/ublock-filters-backup.json`

**Note:** The current export function creates a basic backup structure. For complete backup with all filters, use uBlock Origin UI: Settings → About → Backup to file, then copy that file to `config/ublock-filters-backup.json`.

## Troubleshooting

### Extensions not installing

- Check `/usr/lib/zen-browser/distribution/policies.json` exists
- Restart browser completely
- Check browser console for extension installation errors

### Configuration not applied

- Make sure you ran `setup.sh` after installing the browser
- Check that `~/dotfiles/zen/config/` contains the expected files
- Verify profile directory exists: `~/.zen/*.Default*`

### uBlock filters not importing

- Make sure uBlock Origin is installed
- Check that `config/ublock-filters-backup.json` exists
- Try exporting filters manually from uBlock UI first, then replace the file

### Git auto-commit not working

- Make sure you're in a git repository (`~/dotfiles/.git` or `~/dotfiles/zen/.git`)
- Check git permissions
- Run `git status` to see if there are uncommitted changes
