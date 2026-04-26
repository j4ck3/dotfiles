#!/bin/bash
set -euo pipefail

app_path="${HOME}/.config/ags/media-player.tsx"
repo_app_path="${HOME}/dotfiles/hypr/.config/ags/media-player.tsx"
instance="media-player"
window="media-player"
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

if ags toggle "$window" -i "$instance" >/dev/null 2>&1; then
  exit 0
fi

if command -v hyprctl >/dev/null 2>&1; then
  monitor=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .id' | head -n 1)
  monitor=${monitor:-0}
fi

nohup env AGS_MEDIA_MONITOR="$monitor" ags run "$app_path" >/dev/null 2>&1 &

for _ in {1..20}; do
  if ags toggle "$window" -i "$instance" >/dev/null 2>&1; then
    exit 0
  fi
  sleep 0.05
done

notify-send "Media player unavailable" "Could not start AGS media player popup."
exit 1
