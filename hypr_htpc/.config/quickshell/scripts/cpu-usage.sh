#!/usr/bin/env bash
set -euo pipefail

read -r _ user nice system idle iowait irq softirq steal _ </proc/stat
previous_idle=$((idle + iowait))
previous_total=$((user + nice + system + idle + iowait + irq + softirq + steal))

sleep 0.2

read -r _ user nice system idle iowait irq softirq steal _ </proc/stat
current_idle=$((idle + iowait))
current_total=$((user + nice + system + idle + iowait + irq + softirq + steal))

total_delta=$((current_total - previous_total))
idle_delta=$((current_idle - previous_idle))

if ((total_delta <= 0)); then
  printf '0\n'
else
  printf '%d\n' $(((total_delta - idle_delta) * 100 / total_delta))
fi
