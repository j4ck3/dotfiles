#!/bin/bash
set -euo pipefail

app_path="${HOME}/.config/ags/media-player.tsx"
repo_app_path="${HOME}/dotfiles/hypr/.config/ags/media-player.tsx"
monitor=0

if ! command -v ags >/dev/null 2>&1; then
  notify-send "Media player unavailable" "Install AGS to use the media player popup."
  exit 1
fi

if [[ ! -f "$app_path" && -f "$repo_app_path" ]]; then
  app_path="$repo_app_path"
fi

if [[ ! -f "$app_path" ]]; then
  notify-send "Media player unavailable" "Missing AGS config at ${app_path}."
  exit 1
fi

if command -v hyprctl >/dev/null 2>&1; then
  monitor=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .id' | head -n 1)
  monitor=${monitor:-0}
fi

if ags list 2>/dev/null | rg -qx 'media-player'; then
  ags quit --instance media-player || true
  exit 0
fi

nohup env AGS_MEDIA_MONITOR="$monitor" ags run "$app_path" >/dev/null 2>&1 &
