#!/usr/bin/env bash
# Stop using dotfiles symlinks; install hypr_htpc config as real files in ~/.config.
# Use when Hyprland breaks or you want this machine independent of dotfiles links.

set -euo pipefail

DOTFILES="${DOTFILES:-$HOME/dotfiles}"
SRC="$DOTFILES/hypr_htpc"
STAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="$HOME/.config/.hypr-revert-backup-$STAMP"

mkdir -p "$BACKUP"
for p in hypr waybar quickshell; do
  [[ -e "$HOME/.config/$p" || -L "$HOME/.config/$p" ]] && cp -a "$HOME/.config/$p" "$BACKUP/" 2>/dev/null || true
done
[[ -L "$HOME/.local/bin" ]] && cp -aL "$HOME/.local/bin" "$BACKUP/local-bin" 2>/dev/null || true
[[ -L "$HOME/.local/share/stt" ]] && cp -aL "$HOME/.local/share/stt" "$BACKUP/stt" 2>/dev/null || true

echo "Backed up current links/config to $BACKUP"

# Remove dotfiles symlinks
for p in "$HOME/.config/hypr" "$HOME/.config/waybar" "$HOME/.config/quickshell" "$HOME/.local/bin" "$HOME/.local/share/stt"; do
  [[ -e "$p" || -L "$p" ]] && rm -rf "$p"
done

# Copy hypr_htpc as real directories (not symlinks)
cp -a "$SRC/.config/hypr" "$HOME/.config/hypr"
cp -a "$SRC/.config/waybar" "$HOME/.config/waybar"
[[ -d "$SRC/.config/quickshell" ]] && cp -a "$SRC/.config/quickshell" "$HOME/.config/quickshell"
mkdir -p "$HOME/.local/bin"
cp -a "$SRC/.local/bin/"* "$HOME/.local/bin/" 2>/dev/null || true
chmod +x "$HOME/.local/bin/"* 2>/dev/null || true

echo "Installed local copies from $SRC"
echo "Backup: $BACKUP"
echo
echo "Restart Hyprland from SDDM, or from TTY:"
echo "  loginctl terminate-user \$USER   # logs out, SDDM will restart session"
echo "Or kill and re-login from your display manager."
