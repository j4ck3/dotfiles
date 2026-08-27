#!/bin/bash
# Voice-gated waveform for DictationOverlay (webrtcvad — speech only, not raw mic noise).
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${XDG_RUNTIME_DIR}/pulse/native}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

resolve_mic_source() {
  local name
  name="alsa_input.usb-Creative_Technology_Ltd_Sound_Blaster_Play__3_YDSB1730541001069B-00.analog-stereo"
  if pactl list short sources 2>/dev/null | awk '{print $2}' | rg -qx "$name"; then
    printf '%s\n' "$name"
    return 0
  fi
  name=$(pactl list short sources 2>/dev/null | awk '{print $2}' \
    | rg -i 'blaster|creative' | rg -v '\.monitor$' | head -1) || true
  [[ -n "${name:-}" ]] && { printf '%s\n' "$name"; return 0; }
  pactl get-default-source 2>/dev/null || true
}

export PULSE_SOURCE="$(resolve_mic_source)"
[[ -n "${PULSE_SOURCE:-}" ]] || { echo 'no capture source' >&2; exit 1; }

exec python3 "$SCRIPT_DIR/dictation-waveform.py"
