#!/usr/bin/env bash
# Status JSON for a single workspace button in waybar.
set -euo pipefail

id="${1:?workspace id required}"

icon_for() {
  case "$1" in
    1) echo "j" ;;
    2) echo "k" ;;
    3) echo "l" ;;
    4) echo "ö" ;;
    10) echo "i" ;;
    11) echo "u" ;;
    12) echo "y" ;;
    *) echo "$1" ;;
  esac
}

icon="$(icon_for "$id")"
active_id="$(hyprctl activeworkspace -j | jq -r '.id')"
windows="$(hyprctl workspaces -j | jq -r --argjson id "$id" '.[] | select(.id == $id) | .windows' | head -n 1)"
windows="${windows:-0}"

class=""
if [[ "$active_id" == "$id" ]]; then
  class="active"
elif [[ "$windows" == "0" ]]; then
  class="empty"
fi

jq -n --arg text "$icon" --arg class "$class" '{text: $text, class: $class}'
