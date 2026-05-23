#!/bin/bash
set -euo pipefail

app_path="${HOME}/.config/ags/shortcuts-cheatsheet.tsx"
repo_app_path="${HOME}/dotfiles/hypr/.config/ags/shortcuts-cheatsheet.tsx"
instance="shortcuts-cheatsheet"
window="shortcuts-cheatsheet"
monitor=0

if ! command -v ags >/dev/null 2>&1; then
  notify-send "Shortcuts guide unavailable" "Install AGS to use the keyboard shortcuts overlay."
  exit 1
fi

if [[ ! -f "$app_path" && -f "$repo_app_path" ]]; then
  app_path="$repo_app_path"
fi

if [[ ! -f "$app_path" ]]; then
  notify-send "Shortcuts guide unavailable" "Missing AGS config at ${app_path}."
  exit 1
fi

if ags toggle "$window" -i "$instance" >/dev/null 2>&1; then
  exit 0
fi

# Stale instance from a crashed start: dbus up, window never registered
if ags list 2>/dev/null | rg -qx "$instance"; then
  ags quit -i "$instance" >/dev/null 2>&1 || true
  sleep 0.1
fi

if command -v hyprctl >/dev/null 2>&1; then
  monitor=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .id' | head -n 1)
  monitor=${monitor:-0}
fi

log_file="/tmp/ags-${instance}.log"
nohup env AGS_SHORTCUTS_MONITOR="$monitor" \
  ags run "$app_path" --log-file "$log_file" >/dev/null 2>&1 &

for _ in {1..40}; do
  if ags toggle "$window" -i "$instance" >/dev/null 2>&1; then
    exit 0
  fi
  sleep 0.05
done

detail="Could not start AGS shortcuts overlay."
if [[ -s "$log_file" ]]; then
  detail=$(tail -n 3 "$log_file" | tr '\n' ' ')
fi
notify-send "Shortcuts guide unavailable" "$detail"
exit 1
