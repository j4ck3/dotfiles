# Zen Browser Configuration

Automated setup and sync for Zen Browser settings, extensions, and keybindings.

## Files

```
~/dotfiles/zen/
├── setup.sh      # Install Zen Browser + apply config (run on new machine)
├── export.sh     # Export current settings to config/ (run after changes)
├── config/       # Your saved configuration
│   ├── policies.json                  # Extension auto-install list
│   ├── user.js                        # Browser preferences
│   ├── zen-keyboard-shortcuts.json    # Keyboard shortcuts
│   ├── extension-preferences.json     # Extension permissions
│   ├── extension-settings.json        # Extension command overrides
│   ├── zen-themes.json                # Zen themes config
│   ├── chrome/                        # Custom CSS
│   ├── browser-extension-data/        # Extension local storage
│   └── storage/                       # Extension IndexedDB data
└── README.md
```

## Usage

### On a new machine:
```bash
# 1. Clone your dotfiles
git clone <your-dotfiles-repo> ~/.dotfiles

# 2. Run setup
~/dotfiles/zen/setup.sh
```

### After making changes in the browser:
```bash
# Export your current settings
~/dotfiles/zen/export.sh

# Changes are auto-committed to git
```

## What gets exported/restored

| Setting | Export | Restore |
|---------|--------|---------|
| Extensions | ✅ Auto-generates policies.json | ✅ Auto-installs via policies |
| Keyboard shortcuts | ✅ | ✅ |
| Browser preferences | ✅ Filters user-relevant prefs | ✅ via user.js |
| Extension permissions | ✅ | ✅ |
| Zen themes/CSS | ✅ | ✅ |
| Extension storage (uBlock filters, etc.) | ⚠️ Partial* | ⚠️ Manual |

*Extension storage uses per-install UUIDs, so some settings may need manual reconfiguration.

## Extensions

Your extensions are automatically installed via `policies.json`:

- uBlock Origin
- Dark Reader
- Vimium C
- Bitwarden Password Manager
- SponsorBlock
- Sidebery
- Tree Style Tab
- Startpage Private Search
- Stylus
- I still don't care about cookies
- Enhancer for YouTube
- Floccus bookmarks sync
- MetaMask

## Troubleshooting

### Extensions not installing
1. Check that `policies.json` was deployed to `/usr/lib/zen-browser/distribution/`
2. Restart the browser completely (not just reload)

### Settings not applied
1. Make sure the browser was closed when running `setup.sh`
2. Check that `user.js` exists in your profile directory

### Export failing
1. Close Zen Browser before exporting
2. Check that your profile exists in `~/.zen/`

