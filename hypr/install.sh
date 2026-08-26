#!/usr/bin/env bash
# Link a Hyprland profile and its optional desktop-shell config into $HOME.
# Usage: ./install.sh [hypr|hypr_htpc]   (default: hypr)

set -euo pipefail

PROFILE="${1:-hypr}"
DOTFILES="${DOTFILES:-$HOME/dotfiles}"
SRC="$DOTFILES/$PROFILE"

if [[ ! -d "$SRC/.config/hypr" ]]; then
  echo "error: $SRC/.config/hypr not found" >&2
  exit 1
fi

link_path() {
  local target=$1
  local link=$2
  mkdir -p "$(dirname "$link")"
  if [[ -L "$link" && "$(readlink -f "$link")" == "$(readlink -f "$target")" ]]; then
    echo "already linked: $link"
    return
  fi
  if [[ -e "$link" || -L "$link" ]]; then
    rm -rf "$link"
  fi
  ln -sfn "$target" "$link"
  echo "linked $link -> $target"
}

echo "Installing dotfiles profile: $PROFILE"

link_path "$SRC/.config/hypr" "$HOME/.config/hypr"

if [[ -d "$SRC/.config/waybar" ]]; then
  link_path "$SRC/.config/waybar" "$HOME/.config/waybar"
fi

if [[ -f "$SRC/.config/helium-browser-flags.conf" ]]; then
  link_path "$SRC/.config/helium-browser-flags.conf" "$HOME/.config/helium-browser-flags.conf"
fi

if [[ -f "$SRC/.config/spotify-flags.conf" ]]; then
  link_path "$SRC/.config/spotify-flags.conf" "$HOME/.config/spotify-flags.conf"
fi

if [[ -d "$SRC/.config/quickshell" ]]; then
  link_path "$SRC/.config/quickshell" "$HOME/.config/quickshell"
fi

if [[ -d "$SRC/.config/vimium-c" ]]; then
  link_path "$SRC/.config/vimium-c" "$HOME/.config/vimium-c"
fi

for scripts_dir in \
  "$SRC/.config/hypr/scripts" \
  "$SRC/.config/quickshell/scripts" \
  "$SRC/.config/waybar/scripts"; do
  if [[ -d "$scripts_dir" ]]; then
    chmod +x "$scripts_dir"/* 2>/dev/null || true
  fi
done

if [[ -d "$SRC/.local/bin" ]]; then
  mkdir -p "$HOME/.local/bin"
  for bin in "$SRC/.local/bin"/*; do
    [[ -f "$bin" ]] || continue
    name=$(basename "$bin")
    chmod +x "$bin" 2>/dev/null || true
    link_path "$bin" "$HOME/.local/bin/$name"
  done
fi

if [[ -d "$SRC/.local/share/stt" ]]; then
  link_path "$SRC/.local/share/stt" "$HOME/.local/share/stt"
fi

if [[ -f "$SRC/99-keyboard-wake.rules" ]]; then
  echo
  echo "Optional (requires sudo): copy keyboard wake udev rule:"
  echo "  sudo cp $SRC/99-keyboard-wake.rules /etc/udev/rules.d/"
  echo "  sudo udevadm control --reload"
fi

echo
echo "Done. Reload Hyprland when in a session:"
echo "  hyprctl reload"
if [[ -f "$HOME/.config/vimium-c/vimium-c.json" ]]; then
  echo
  echo "Vimium C: import ~/.config/vimium-c/vimium-c.json in extension options"
  echo "  (YouTube: f=fullscreen, e/E=link hints)"
fi
