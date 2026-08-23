#!/usr/bin/env bash
# Start waybar with Hyprland IPC (j/k/l/ö workspace buttons need HYPRLAND_INSTANCE_SIGNATURE).
set -euo pipefail

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
  for lock in "$runtime"/hypr/*/hyprland.lock; do
    [[ -f "$lock" ]] || continue
    export HYPRLAND_INSTANCE_SIGNATURE
    HYPRLAND_INSTANCE_SIGNATURE=$(basename "$(dirname "$lock")")
    break
  done
fi

if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
  echo "waybar-start: Hyprland not running (no HYPRLAND_INSTANCE_SIGNATURE)" >&2
  exit 1
fi

exec waybar "$@"
