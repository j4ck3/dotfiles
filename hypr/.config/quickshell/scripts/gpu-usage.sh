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

find_amd_gpu_junction_input() {
  local hwmon label_file path

  for hwmon in /sys/class/hwmon/hwmon*; do
    [ "$(<"$hwmon/name")" = amdgpu ] || continue

    for path in "$hwmon"/temp*_input; do
      [ -r "$path" ] || continue
      label_file="${path%_input}_label"
      [ -r "$label_file" ] || continue
      if grep -qx 'junction' "$label_file"; then
        printf '%s\n' "$path"
        return 0
      fi
    done
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

temp_input=$(find_amd_gpu_junction_input)
if [ -n "$temp_input" ]; then
  temp=$(($( <"$temp_input") / 1000))
else
  temp=""
fi

if [ -r "$device/mem_info_vram_used" ] && [ -r "$device/mem_info_vram_total" ]; then
  vram_used=$(<"$device/mem_info_vram_used")
  vram_total=$(<"$device/mem_info_vram_total")
  if [ -n "$temp" ]; then
    tooltip=$(printf 'AMD GPU\nUsage: %s%%\nJunction: %s°C\nVRAM: %s / %s' "$usage" "$temp" "$(format_gib "$vram_used")" "$(format_gib "$vram_total")")
  else
    tooltip=$(printf 'AMD GPU\nUsage: %s%%\nVRAM: %s / %s' "$usage" "$(format_gib "$vram_used")" "$(format_gib "$vram_total")")
  fi
else
  if [ -n "$temp" ]; then
    tooltip=$(printf 'AMD GPU\nUsage: %s%%\nJunction: %s°C' "$usage" "$temp")
  else
    tooltip=$(printf 'AMD GPU\nUsage: %s%%' "$usage")
  fi
fi

class=""
if [ "$usage" -ge 70 ] || { [ -n "$temp" ] && [ "$temp" -ge 85 ]; }; then
  class="high"
fi

if [ -n "$temp" ]; then
  text=$(printf '<span size="x-small">GPU</span>\n%s%% · %s°C' "$usage" "$temp")
else
  text=$(printf '<span size="x-small">GPU</span>\n%s%%' "$usage")
fi

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(printf '%s' "$text" | escape_json)" \
  "$(printf '%s' "$tooltip" | escape_json)" \
  "$class"
