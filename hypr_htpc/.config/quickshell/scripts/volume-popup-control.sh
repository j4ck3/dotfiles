#!/bin/bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <set|toggle-mute> <sink|source|stream> <id> [value]" >&2
  exit 1
fi

action=$1
target=$2
id=$3
value=${4:-}

case "$action:$target" in
  set:sink)
    pactl set-sink-volume "$id" "${value}%"
    ;;
  set:source)
    pactl set-source-volume "$id" "${value}%"
    ;;
  set:stream)
    pactl set-sink-input-volume "$id" "${value}%"
    ;;
  toggle-mute:sink)
    pactl set-sink-mute "$id" toggle
    ;;
  toggle-mute:source)
    pactl set-source-mute "$id" toggle
    ;;
  toggle-mute:stream)
    pactl set-sink-input-mute "$id" toggle
    ;;
  *)
    echo "unsupported command: $action $target" >&2
    exit 1
    ;;
esac
