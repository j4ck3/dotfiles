#!/bin/bash
trap 'exit 0' PIPE

threshold_bytes_per_sec=1875000

get_default_iface() {
  ip route show default 2>/dev/null | awk '
    NR == 1 {
      for (i = 1; i <= NF; i++) {
        if ($i == "dev") {
          print $(i + 1)
          exit
        }
      }
    }'
}

format_rate() {
  local bytes_per_sec="$1"

  if [ "$bytes_per_sec" -lt 1024 ]; then
    printf "%d B/s" "$bytes_per_sec"
  elif [ "$bytes_per_sec" -lt 1048576 ]; then
    printf "%d KB/s" $((bytes_per_sec / 1024))
  else
    awk -v rate="$bytes_per_sec" 'BEGIN { printf "%.1f MB/s", rate / 1048576 }'
  fi
}

output_disconnected() {
  printf '{"text":"","class":"hidden","tooltip":"Network disconnected"}\n'
}

output_hidden() {
  printf '{"text":"","class":"hidden","tooltip":""}\n'
}

last_iface=""
last_rx=0
last_tx=0
last_ts=0

while true; do
  iface=$(get_default_iface)

  if [ -z "$iface" ] || [ ! -r "/sys/class/net/$iface/statistics/rx_bytes" ] || [ ! -r "/sys/class/net/$iface/statistics/tx_bytes" ]; then
    output_disconnected
    last_iface=""
    sleep 1
    continue
  fi

  rx=$(<"/sys/class/net/$iface/statistics/rx_bytes")
  tx=$(<"/sys/class/net/$iface/statistics/tx_bytes")
  ts=$(date +%s)

  if [ "$iface" != "$last_iface" ] || [ "$last_ts" -eq 0 ] || [ "$ts" -le "$last_ts" ]; then
    down_rate=0
    up_rate=0
  else
    elapsed=$((ts - last_ts))
    down_rate=$(((rx - last_rx) / elapsed))
    up_rate=$(((tx - last_tx) / elapsed))
    [ "$down_rate" -lt 0 ] && down_rate=0
    [ "$up_rate" -lt 0 ] && up_rate=0
  fi

  down_text=$(format_rate "$down_rate")
  up_text=$(format_rate "$up_rate")

  if [ "$down_rate" -lt "$threshold_bytes_per_sec" ] && [ "$up_rate" -lt "$threshold_bytes_per_sec" ]; then
    output_hidden
    last_iface="$iface"
    last_rx="$rx"
    last_tx="$tx"
    last_ts="$ts"
    sleep 1
    continue
  fi

  text=$(printf '⇡ %s\n⇣ %s' "$up_text" "$down_text")
  tooltip=$(printf '%s\nDown: %s\nUp: %s' "$iface" "$down_text" "$up_text")
  text_escaped=$(printf '%s' "$text" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s%s", (NR>1?"\\n":""), $0}')
  tooltip_escaped=$(printf '%s' "$tooltip" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s%s", (NR>1?"\\n":""), $0}')

  printf '{"text":"%s","tooltip":"%s"}\n' "$text_escaped" "$tooltip_escaped"

  last_iface="$iface"
  last_rx="$rx"
  last_tx="$tx"
  last_ts="$ts"
  sleep 1
done
