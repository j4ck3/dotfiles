#!/bin/bash
set -euo pipefail

# Brief tone so auto-on external speakers detect output and power up.
duration=0.4
volume=0.12

if command -v pw-play >/dev/null 2>&1; then
  player=pw-play
elif command -v paplay >/dev/null 2>&1; then
  player=paplay
else
  notify-send "Wake speakers" "No audio player (pw-play/paplay) found."
  exit 1
fi

ffmpeg -nostdin -hide_banner -loglevel error \
  -f lavfi -i "sine=frequency=440:duration=${duration}" \
  -af "volume=${volume}" -f wav - | "$player" -
