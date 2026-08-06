#!/usr/bin/env bash
# Stop the stealth VM, apply an XML mutation, boot it, and capture the screen.
# Usage: MUTATE=<python-file> vmtest-boot.sh <shot-name> [settle-seconds]
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${DOMAIN:-windows11-stealth}"
URI="qemu:///system"
name="${1:-boot}"
settle="${2:-100}"

if [[ "$(virsh -c "${URI}" domstate "${DOMAIN}" 2>/dev/null)" == "running" ]]; then
  echo "destroying ${DOMAIN}..."
  virsh -c "${URI}" destroy "${DOMAIN}" >/dev/null 2>&1
  for _ in $(seq 1 30); do
    [[ "$(virsh -c "${URI}" domstate "${DOMAIN}" 2>/dev/null)" != "running" ]] && break
    sleep 2
  done
fi

if [[ -n "${MUTATE:-}" ]]; then
  tmp="$(mktemp --suffix=.xml)"
  python3 "${MUTATE}" > "${tmp}" || { echo "mutation failed"; exit 1; }
  virsh -c "${URI}" define "${tmp}" >/dev/null || { echo "define failed"; exit 1; }
  rm -f "${tmp}"
  echo "applied mutation: ${MUTATE}"
fi

echo "starting ${DOMAIN}..."
DOMAIN="${DOMAIN}" /usr/local/bin/windows11-stealth-start --yes >/dev/null 2>&1
sleep "${settle}"

virsh -c "${URI}" screenshot "${DOMAIN}" "/tmp/${name}.ppm" >/dev/null 2>&1
magick "/tmp/${name}.ppm" "/tmp/${name}.png"
rd="$(virsh -c "${URI}" domstats "${DOMAIN}" --block 2>/dev/null | awk -F= '/block.0.rd.bytes/{print $2}')"
echo "captured /tmp/${name}.png rd=${rd}"
