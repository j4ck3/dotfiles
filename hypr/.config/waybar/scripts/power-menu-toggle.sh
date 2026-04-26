#!/bin/bash
set -euo pipefail

app_path="${HOME}/.config/ags/power-menu.tsx"
repo_app_path="${HOME}/dotfiles/hypr/.config/ags/power-menu.tsx"
instance="power-menu"
window="power-menu"
monitor=0

if ! command -v ags >/dev/null 2>&1; then
  notify-send "Power menu unavailable" "Install AGS to use the power menu popup."
  exit 1
fi

if [[ ! -f "$app_path" && -f "$repo_app_path" ]]; then
  app_path="$repo_app_path"
fi

if [[ ! -f "$app_path" ]]; then
  notify-send "Power menu unavailable" "Missing AGS config at ${app_path}."
  exit 1
fi

if ags toggle "$window" -i "$instance" >/dev/null 2>&1; then
  exit 0
fi

if command -v hyprctl >/dev/null 2>&1; then
  monitor=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .id' | head -n 1)
  monitor=${monitor:-0}
fi

nohup env AGS_POWER_MONITOR="$monitor" ags run "$app_path" >/dev/null 2>&1 &

for _ in {1..20}; do
  if ags toggle "$window" -i "$instance" >/dev/null 2>&1; then
    exit 0
  fi
  sleep 0.05
done

notify-send "Power menu unavailable" "Could not start AGS power menu popup."
exit 1
