#!/usr/bin/env bash
set -euo pipefail

state_dir="${XDG_RUNTIME_DIR:-/tmp}/display-popup"
mkdir -p "$state_dir"

brightness_file="$state_dir/hdr-brightness"
blue_file="$state_dir/bluelight"

brightness=$(cat "$brightness_file" 2>/dev/null || echo 100)
bluelight=$(cat "$blue_file" 2>/dev/null || echo 0)

monitor_json=$(hyprctl monitors -j | jq '.[0]')
mode=$(
  jq -r '
    if .width == 3840 and .height == 2160 and (.refreshRate | round) == 60 then "desktop"
    elif .width == 2560 and .height == 1440 and (.refreshRate | round) == 120 then "fallback"
    elif .width == 3840 and .height == 2160 and (.refreshRate | round) == 24 then "movie"
    else "custom"
    end
  ' <<<"$monitor_json"
)

jq -n \
  --argjson monitor "$monitor_json" \
  --arg mode "$mode" \
  --argjson brightness "$brightness" \
  --argjson bluelight "$bluelight" '
  {
    monitor: {
      name: $monitor.name,
      description: $monitor.description,
      width: $monitor.width,
      height: $monitor.height,
      refreshRate: $monitor.refreshRate,
      format: $monitor.currentFormat,
      color: $monitor.colorManagementPreset
    },
    mode: $mode,
    hdr: (($monitor.colorManagementPreset // "") == "hdr"),
    hdrBrightness: $brightness,
    bluelight: $bluelight,
    presets: [
      { id: "desktop", label: "4K 60", detail: "3840x2160 @ 60 Hz" },
      { id: "fallback", label: "1440p 120 HDR", detail: "2560x1440 @ 120 Hz HDR" },
      { id: "movie", label: "4K 24 HDR", detail: "3840x2160 @ 24 Hz HDR" }
    ]
  }'
