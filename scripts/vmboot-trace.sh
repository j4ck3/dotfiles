#!/usr/bin/env bash
# Boot the stealth VM and capture dense early frames, so a fast-scrolling
# sos driver list is caught before a bugcheck screen overwrites it.
#
# Usage: vmboot-trace.sh [out-dir] [frames] [interval-seconds]
set -uo pipefail

DOMAIN="${DOMAIN:-windows11-stealth}"
URI="qemu:///system"
OUT="${1:-/tmp/trace}"
frames="${2:-45}"
interval="${3:-2}"

rm -rf "${OUT}"
mkdir -p "${OUT}"

if virsh -c "${URI}" domstate "${DOMAIN}" 2>/dev/null | grep -q 'kör\|running'; then
  virsh -c "${URI}" destroy "${DOMAIN}" >/dev/null 2>&1
  sleep 3
fi

echo "starting ${DOMAIN}..."
DOMAIN="${DOMAIN}" /usr/local/bin/windows11-stealth-start --yes >/dev/null 2>&1 &
start_pid=$!

prev=""
for ((i = 1; i <= frames; i++)); do
  sleep "${interval}"
  ppm="${OUT}/f$(printf '%03d' "${i}").ppm"
  if ! virsh -c "${URI}" screenshot "${DOMAIN}" "${ppm}" >/dev/null 2>&1; then
    echo "f${i}: no screenshot (domain not ready)"
    continue
  fi
  png="${ppm%.ppm}.png"
  magick "${ppm}" "${png}" 2>/dev/null
  rm -f "${ppm}"
  sum="$(sha256sum "${png}" | cut -c1-12)"
  if [[ "${sum}" == "${prev}" ]]; then
    rm -f "${png}"
    continue
  fi
  prev="${sum}"
  colors="$(magick identify -format '%k' "${png}" 2>/dev/null)"
  rd="$(virsh -c "${URI}" domstats "${DOMAIN}" --block 2>/dev/null | awk -F= '/block.0.rd.bytes/{print $2}')"
  echo "f${i} t=$((i * interval))s colors=${colors} rd=${rd} -> ${png}"
done

wait "${start_pid}" 2>/dev/null
echo "kept frames: $(ls "${OUT}"/*.png 2>/dev/null | wc -l)"
