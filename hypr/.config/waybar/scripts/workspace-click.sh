#!/usr/bin/env bash
# Hyprland 0.55+ needs Lua dispatch; waybar 0.15's built-in workspace clicks use the old format.
set -euo pipefail

id="${1:?workspace id required}"
hyprctl dispatch "hl.dsp.focus({ workspace = ${id}, on_current_monitor = true })"
