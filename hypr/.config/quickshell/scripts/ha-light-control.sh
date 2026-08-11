#!/bin/bash
# Control Home Assistant light from Quickshell PowerMenu.
# Usage:
#   ha-light-control.sh toggle|on|off
#   ha-light-control.sh set <0-100>
#   ha-light-control.sh hs <hue0-360> <sat0-100>
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/ha-common.sh"

usage() {
  echo "Usage: $0 toggle|on|off|set <0-100>|hs <hue> <sat>" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
cmd="$1"

post_service() {
  local service="$1"
  local body="$2"
  ha_curl POST "/api/services/light/${service}" -d "$body" >/dev/null
}

entity_body() {
  printf '{"entity_id":"%s"}' "$HA_ENTITY"
}

clamp_int() {
  local v="$1"
  local lo="$2"
  local hi="$3"
  if (( v < lo )); then v=$lo; fi
  if (( v > hi )); then v=$hi; fi
  printf '%s' "$v"
}

case "$cmd" in
  toggle)
    post_service toggle "$(entity_body)"
    ;;
  on)
    post_service turn_on "$(entity_body)"
    ;;
  off)
    post_service turn_off "$(entity_body)"
    ;;
  set)
    [[ $# -eq 2 ]] || usage
    pct="$2"
    if ! [[ "$pct" =~ ^[0-9]+$ ]]; then
      usage
    fi
    pct="$(clamp_int "$pct" 0 100)"
    if (( pct == 0 )); then
      post_service turn_off "$(entity_body)"
    else
      post_service turn_on "$(printf '{"entity_id":"%s","brightness_pct":%s}' "$HA_ENTITY" "$pct")"
    fi
    ;;
  hs)
    [[ $# -eq 3 ]] || usage
    hue="$2"
    sat="$3"
    # Allow decimals from the wheel
    if ! [[ "$hue" =~ ^[0-9]+([.][0-9]+)?$ && "$sat" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
      usage
    fi
    # Clamp floats (avoid `read` + set -e EOF trap)
    hue="$(awk -v h="$hue" 'BEGIN {
      if (h < 0) h = 0
      if (h >= 360) h = h % 360
      printf "%.3f", h
    }')"
    sat="$(awk -v s="$sat" 'BEGIN {
      if (s < 0) s = 0
      if (s > 100) s = 100
      printf "%.3f", s
    }')"
    post_service turn_on "$(printf '{"entity_id":"%s","hs_color":[%s,%s]}' "$HA_ENTITY" "$hue" "$sat")"
    ;;
  *)
    usage
    ;;
esac
