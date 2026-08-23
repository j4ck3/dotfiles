#!/usr/bin/env bash
# Install Arch/CachyOS packages used by the hypr dotfiles profile.
# AUR-only tools are listed at the end (install separately if you want them).

set -euo pipefail

PACMAN_PACKAGES=(
  # Hyprland stack
  hyprland waybar quickshell hypridle hyprlock hyprsunset hyprpicker
  # hyprpm (topgrade step) build deps
  cmake cpio
  # Screenshots / clipboard / color picker
  grim slurp wl-clipboard satty
  # Audio / media / notifications
  playerctl pavucontrol brightnessctl libnotify ffmpeg mpv
  # Waybar modules / scripts
  jq socat networkmanager
  # Apps & terminals (bindings + autostart)
  uwsm walker helium-browser-bin nautilus ghostty
  lazydocker lazygit btop opencode
  fzf fd tmux neovim
  # Voice / OCR helpers
  yad tesseract tesseract-data-eng tesseract-data-swe
  # Optional waybar docker module
  docker
  # Whisper STT (used by ~/.local/share/stt; venv setup is separate)
  python-openai-whisper
)

echo "Synchronizing the system and installing pacman packages..."
# Arch/CachyOS does not support partial upgrades. Refresh package databases and
# upgrade the system in the same transaction so repository package URLs and
# dependency versions cannot be stale.
sudo pacman -Syu --needed --noconfirm "${PACMAN_PACKAGES[@]}"

cat <<'EOF'

Installed repo packages. Optional extras (not in official repos on all systems):

  # Omarchy launcher stack (Super+Space) — install matching elephant + walker
  yay -S --needed elephant elephant-desktopapplications

  # Bluetooth tray module
  yay -S --needed blueberry-wayland

  # Spotify (flatpak is common on Omarchy; pick one)
  flatpak install -y flathub com.spotify.Client

STT / TTS one-time setup (after pacman install):
  python -m venv ~/.local/share/stt/.venv
  ~/.local/share/stt/.venv/bin/pip install openai-whisper piper-tts
  mkdir -p ~/.local/share/piper-voices
  # Piper voice: https://rhasspy.github.io/piper-samples/

Hyprlock uses Omarchy themes if present:
  ~/.config/omarchy/current/theme/hyprlock.conf

Edit monitor layout for this machine:
  ~/.config/hypr/monitors.conf   (run: hyprctl monitors all)

EOF
