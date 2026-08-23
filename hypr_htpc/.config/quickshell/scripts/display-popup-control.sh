#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <mode|hdr|brightness|bluelight> [value]" >&2
  exit 1
fi

state_dir="${XDG_RUNTIME_DIR:-/tmp}/display-popup"
mkdir -p "$state_dir"

brightness_file="$state_dir/hdr-brightness"
blue_file="$state_dir/bluelight"
shader_file="$state_dir/display.frag"
log_file="/tmp/display-popup.log"
display_mode_bin="${HOME}/.local/bin/hypr-display-mode"
hyprsunset_ready_file="$state_dir/hyprsunset-ready"

monitor="HDMI-A-1"
action=$1
value=${2:-}

log() {
  printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$log_file"
}

run_logged() {
  log "run: $*"
  "$@" >>"$log_file" 2>&1
}

clamp() {
  local n=${1:-0} min=$2 max=$3
  if (( n < min )); then n=$min; fi
  if (( n > max )); then n=$max; fi
  printf '%s\n' "$n"
}

read_brightness() {
  local raw=100
  if [[ -f "$brightness_file" ]]; then
    raw=$(<"$brightness_file")
    raw=${raw:-100}
  fi
  clamp "$raw" 50 200
}

read_bluelight() {
  local raw=0
  if [[ -f "$blue_file" ]]; then
    raw=$(<"$blue_file")
    raw=${raw:-0}
  fi
  clamp "$raw" 0 100
}

in_hdr() {
  [[ "$(hyprctl monitors -j | jq -r '.[0].colorManagementPreset')" == "hdr" ]]
}

current_mode_spec() {
  hyprctl monitors -j | jq -r '.[0] | "\(.width)x\(.height)@\(.refreshRate | round)"'
}

sdr_brightness_float() {
  awk -v v="${1:-100}" 'BEGIN { printf "%.2f", v / 100 }'
}

# HTPC uses Hyprland Lua config: hyprctl keyword is rejected ("non-legacy parsers").
hypr_eval() {
  local expr=$1
  log "eval: ${expr}"
  hyprctl eval "${expr}" >>"$log_file" 2>&1
}

clear_screen_shader() {
  hypr_eval 'hl.config({ decoration = { screen_shader = "" } })' || true
  rm -f "$shader_file" "$state_dir/bluelight.frag"
}

hyprsunset_connected() {
  hyprctl hyprsunset gamma >/dev/null 2>&1
}

# Gamma IPC via hyprsunset avoids screen_shader reloads (those flicker while dragging).
ensure_hyprsunset() {
  if hyprsunset_connected; then
    if [[ ! -f "$hyprsunset_ready_file" ]]; then
      clear_screen_shader
      printf '1\n' >"$hyprsunset_ready_file"
    fi
    return 0
  fi

  if ! command -v hyprsunset >/dev/null 2>&1; then
    log "hyprsunset missing"
    return 1
  fi

  log "starting hyprsunset"
  hyprsunset >/dev/null 2>&1 &
  disown || true

  local i
  for i in $(seq 1 40); do
    if hyprsunset_connected; then
      clear_screen_shader
      # Restore last QS values (profile defaults would otherwise win).
      hyprctl hyprsunset gamma "$(read_brightness)" >>"$log_file" 2>&1 || true
      local blue
      blue=$(read_bluelight)
      if (( blue > 0 )); then
        apply_temperature "$blue"
      else
        hyprctl hyprsunset identity >>"$log_file" 2>&1 || true
      fi
      printf '1\n' >"$hyprsunset_ready_file"
      return 0
    fi
    sleep 0.05
  done

  log "hyprsunset failed to become ready"
  return 1
}

apply_gamma() {
  local brightness=$1
  ensure_hyprsunset || return 0
  log "hyprsunset gamma ${brightness}"
  hyprctl hyprsunset gamma "$brightness" >>"$log_file" 2>&1 || true
}

# 0% → identity (no warm filter). 100% → ~3000K.
apply_temperature() {
  local strength=$1
  ensure_hyprsunset || return 0

  if (( strength <= 0 )); then
    log "hyprsunset identity (bluelight off)"
    hyprctl hyprsunset identity >>"$log_file" 2>&1 || true
    return
  fi

  local kelvin
  kelvin=$(awk -v v="$strength" 'BEGIN { printf "%d", 6500 - (v * 35) }')
  if (( kelvin < 3000 )); then kelvin=3000; fi
  if (( kelvin > 6500 )); then kelvin=6500; fi

  log "hyprsunset temperature ${kelvin} (bluelight ${strength})"
  hyprctl hyprsunset temperature "$kelvin" >>"$log_file" 2>&1 || true
}

# Keep HDR tonemap matched when enabling HDR. Live slider dragging uses gamma only
# so hl.monitor updates (which can flicker) are not on the hot path.
apply_brightness() {
  local brightness
  brightness=$(clamp "${1:-100}" 50 200)
  printf '%s\n' "$brightness" >"$brightness_file"
  log "brightness ${brightness}"
  apply_gamma "$brightness"
}

apply_bluelight() {
  local strength
  strength=$(clamp "${1:-0}" 0 100)
  printf '%s\n' "$strength" >"$blue_file"
  log "bluelight ${strength}"
  apply_temperature "$strength"
}

apply_current_with_color() {
  local cm=$1
  local brightness=${2:-$(read_brightness)}
  local bitdepth=8
  local spec sdr_b

  spec=$(current_mode_spec)
  sdr_b=$(sdr_brightness_float "$brightness")

  if [[ "$cm" == "hdr" ]]; then
    bitdepth=10
  fi

  log "monitor color: ${monitor}, ${spec}, bitdepth ${bitdepth}, cm ${cm}, sdrbrightness ${sdr_b}"
  if [[ "$cm" == "hdr" ]]; then
    hypr_eval "hl.monitor({ output = \"${monitor}\", mode = \"${spec}\", position = \"0x0\", scale = 1, bitdepth = ${bitdepth}, cm = \"${cm}\", sdrbrightness = ${sdr_b} })"
  else
    hypr_eval "hl.monitor({ output = \"${monitor}\", mode = \"${spec}\", position = \"0x0\", scale = 1, bitdepth = ${bitdepth}, cm = \"${cm}\" })"
  fi

  # Restore gamma/temperature after modeset (compositor path is independent, but re-assert state).
  apply_gamma "$brightness"
  apply_temperature "$(read_bluelight)"
}

case "$action" in
  mode)
    case "$value" in
      desktop|fallback|movie) run_logged "$display_mode_bin" "$value" ;;
      *) echo "unknown mode: $value" >&2; exit 1 ;;
    esac
    ;;
  hdr)
    case "$value" in
      on) log "hdr on"; apply_current_with_color hdr ;;
      off) log "hdr off"; apply_current_with_color srgb ;;
      toggle)
        log "hdr toggle"
        if in_hdr; then
          apply_current_with_color srgb
        else
          apply_current_with_color hdr
        fi
        ;;
      *) echo "usage: $0 hdr <on|off|toggle>" >&2; exit 1 ;;
    esac
    ;;
  brightness)
    apply_brightness "${value:-100}"
    ;;
  bluelight)
    apply_bluelight "${value:-0}"
    ;;
  *)
    echo "unknown action: $action" >&2
    exit 1
    ;;
esac
