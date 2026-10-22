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

find_coretemp_package_input() {
  local hwmon label_file path

  for hwmon in /sys/class/hwmon/hwmon*; do
    [ "$(<"$hwmon/name")" = coretemp ] || continue

    for path in "$hwmon"/temp*_input; do
      [ -r "$path" ] || continue
      label_file="${path%_input}_label"
      [ -r "$label_file" ] || continue
      if grep -q '^Package id' "$label_file"; then
        printf '%s\n' "$path"
        return 0
      fi
    done
  done

  return 1
}

read_cpu_usage() {
  local stat_file=/tmp/waybar-cpu-stat
  local user nice system idle iowait irq softirq steal
  local active total prev_active prev_total usage

  read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
  active=$((user + nice + system + irq + softirq + steal))
  total=$((active + idle + iowait))

  if [ -f "$stat_file" ]; then
    read -r prev_active prev_total < "$stat_file"
    if [ "$((total - prev_total))" -gt 0 ]; then
      usage=$(((active - prev_active) * 100 / (total - prev_total)))
    else
      usage=0
    fi
  else
    usage=0
  fi

  printf '%s %s\n' "$active" "$total" >"$stat_file"
  printf '%s\n' "$usage"
}

read_cpu_temp() {
  local input=$1
  local milli

  milli=$(<"$input")
  printf '%s\n' $((milli / 1000))
}

read_thermal_throttle() {
  local throttle_dir=/sys/devices/system/cpu/cpu0/thermal_throttle
  local state_file=/tmp/waybar-cpu-throttle-stat
  local pkg_count pkg_time_ms prev_count=0 prev_time_ms=0 throttling=0

  [ -r "$throttle_dir/package_throttle_count" ] || return 1
  [ -r "$throttle_dir/package_throttle_total_time_ms" ] || return 1

  pkg_count=$(<"$throttle_dir/package_throttle_count")
  pkg_time_ms=$(<"$throttle_dir/package_throttle_total_time_ms")

  if [ -f "$state_file" ]; then
    read -r prev_count prev_time_ms <"$state_file" || true
    prev_count=${prev_count:-0}
    prev_time_ms=${prev_time_ms:-0}
    if [ "$pkg_count" -gt "$prev_count" ] || [ "$pkg_time_ms" -gt "$prev_time_ms" ]; then
      throttling=1
    fi
  fi

  printf '%s %s\n' "$pkg_count" "$pkg_time_ms" >"$state_file"
  THROTTLE_ACTIVE=$throttling
  THROTTLE_COUNT=$pkg_count
  THROTTLE_TIME_MS=$pkg_time_ms
}

usage=$(read_cpu_usage)
temp_input=$(find_coretemp_package_input)
THROTTLE_ACTIVE=0
THROTTLE_COUNT=0
THROTTLE_TIME_MS=0
read_thermal_throttle || true

throttle_suffix=""
if [ "$THROTTLE_ACTIVE" -eq 1 ]; then
  throttle_suffix=" · THR"
fi

if [ -z "$temp_input" ]; then
  text=$(printf '<span size="x-small">CPU</span>\n%s%%%s' "$usage" "$throttle_suffix")
  tooltip=$(printf 'CPU usage: %s%%' "$usage")
  class=""
  if [ "$usage" -gt 90 ]; then
    class="high"
  fi
else
  temp=$(read_cpu_temp "$temp_input")
  text=$(printf '<span size="x-small">CPU</span>\n%s%%%s' "$usage" "$throttle_suffix")
  tooltip=$(printf 'CPU\nUsage: %s%%\nPackage: %s°C' "$usage" "$temp")
  class=""
  if [ "$usage" -gt 90 ] || [ "$temp" -gt 90 ]; then
    class="high"
  fi
fi

if [ "$THROTTLE_ACTIVE" -eq 1 ]; then
  tooltip=$(printf '%s\nThermal throttle: active now' "$tooltip")
elif [ "$THROTTLE_COUNT" -gt 0 ]; then
  if [ "$THROTTLE_TIME_MS" -ge 1000 ]; then
    throttle_time=$((THROTTLE_TIME_MS / 1000))
    tooltip=$(printf '%s\nThermal throttle (boot): %s events, %ss total' "$tooltip" "$THROTTLE_COUNT" "$throttle_time")
  else
    tooltip=$(printf '%s\nThermal throttle (boot): %s events, %sms total' "$tooltip" "$THROTTLE_COUNT" "$THROTTLE_TIME_MS")
  fi
fi

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(printf '%s' "$text" | escape_json)" \
  "$(printf '%s' "$tooltip" | escape_json)" \
  "$class"
