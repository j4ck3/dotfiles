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

usage=$(read_cpu_usage)
temp_input=$(find_coretemp_package_input)

if [ -z "$temp_input" ]; then
  text=$(printf '<span size="x-small">CPU</span>\n%s%%' "$usage")
  tooltip=$(printf 'CPU usage: %s%%' "$usage")
  class=""
  if [ "$usage" -ge 70 ]; then
    class="high"
  fi
else
  temp=$(read_cpu_temp "$temp_input")
  text=$(printf '<span size="x-small">CPU</span>\n%s%% · %s°C' "$usage" "$temp")
  tooltip=$(printf 'CPU\nUsage: %s%%\nPackage: %s°C' "$usage" "$temp")
  class=""
  if [ "$usage" -ge 70 ] || [ "$temp" -ge 80 ]; then
    class="high"
  fi
fi

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' \
  "$(printf '%s' "$text" | escape_json)" \
  "$(printf '%s' "$tooltip" | escape_json)" \
  "$class"
