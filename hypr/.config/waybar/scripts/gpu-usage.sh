#!/bin/bash
trap 'exit 0' PIPE

escape_json() {
  awk '
    BEGIN { ORS = ""; sep = "" }
    {
      gsub(/\\/, "\\\\")
      gsub(/"/, "\\\"")
      printf "%s%s", sep, $0
      sep = "\\n"
    }
  '
}

find_amd_gpu_device() {
  local card base device

  for card in /sys/class/drm/card*; do
    [ -d "$card/device" ] || continue
    base=${card##*/}

    if [[ ! "$base" =~ ^card[0-9]+$ ]]; then
      continue
    fi

    device="$card/device"
    if grep -q '^DRIVER=amdgpu$' "$device/uevent" 2>/dev/null && [ -r "$device/gpu_busy_percent" ]; then
      printf '%s\n' "$device"
      return 0
    fi
  done

  return 1
}

format_gib() {
  awk -v bytes="$1" 'BEGIN { printf "%.1f GiB", bytes / 1073741824 }'
}

device=$(find_amd_gpu_device)

if [ -z "$device" ]; then
  printf '{"text":"","class":"hidden","tooltip":"AMD GPU telemetry unavailable"}\n'
  exit 0
fi

usage=$(<"$device/gpu_busy_percent")
usage=${usage%%.*}

if [ -r "$device/mem_info_vram_used" ] && [ -r "$device/mem_info_vram_total" ]; then
  vram_used=$(<"$device/mem_info_vram_used")
  vram_total=$(<"$device/mem_info_vram_total")
  tooltip=$(printf 'AMD GPU\nUsage: %s%%\nVRAM: %s / %s' "$usage" "$(format_gib "$vram_used")" "$(format_gib "$vram_total")")
else
  tooltip=$(printf 'AMD GPU\nUsage: %s%%' "$usage")
fi

class=""
if [ "$usage" -ge 70 ]; then
  class="high"
fi

text=$(printf '<span size="x-small">GPU</span>\n%s%%' "$usage")

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(printf '%s' "$text" | escape_json)" \
  "$(printf '%s' "$tooltip" | escape_json)" \
  "$class"
