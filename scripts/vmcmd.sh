#!/usr/bin/env bash
# Type one command into the guest console, run it, and capture the screen.
# Usage: vmcmd.sh "<command>" <shot-name>
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="${DOMAIN:-windows11-stealth}"
cmd="$1"
name="${2:-shot}"

python3 "${HERE}/vmkeys.py" --domain "${DOMAIN}" --text "${cmd}"
sleep 1
python3 "${HERE}/vmkeys.py" --domain "${DOMAIN}" --key KEY_ENTER
sleep "${SETTLE:-5}"

virsh -c qemu:///system screenshot "${DOMAIN}" "/tmp/${name}.ppm" >/dev/null 2>&1
magick "/tmp/${name}.ppm" "/tmp/${name}.png"
echo "captured /tmp/${name}.png"
