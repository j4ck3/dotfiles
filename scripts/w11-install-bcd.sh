#!/usr/bin/env bash
# Install a prepared BCD store into the stealth guest ESP.
#
# Usage:
#   sudo BCD=/tmp/BCD.patched bash scripts/w11-install-bcd.sh
set -uo pipefail

IMAGE="${IMAGE:-/home/jacke/.local/share/libvirt/images/windows11-stealth.qcow2}"
BCD="${BCD:-/tmp/BCD.patched}"
NBD="${NBD:-/dev/nbd0}"
MNT="$(mktemp -d)"
BACKUP_DIR="${BACKUP_DIR:-/home/jacke/.cache/windows11-stealth-debug}"

[[ ${EUID} -eq 0 ]] || { echo "run as root" >&2; exit 1; }
[[ -s "${BCD}" ]] || { echo "missing BCD ${BCD}" >&2; exit 1; }

if virsh -c qemu:///system domstate windows11-stealth 2>/dev/null | grep -q running; then
  echo "REFUSING: windows11-stealth is running" >&2
  exit 1
fi

cleanup() {
  mountpoint -q "${MNT}" && umount "${MNT}"
  qemu-nbd --disconnect "${NBD}" >/dev/null 2>&1
  rmdir "${MNT}" 2>/dev/null
}
trap cleanup EXIT

modprobe nbd max_part=16
qemu-nbd --connect="${NBD}" "${IMAGE}" || exit 1
sleep 1
partx -u "${NBD}" >/dev/null 2>&1

esp=""
for part in "${NBD}"p*; do
  [[ -b "${part}" ]] || continue
  if mount -t vfat -o rw "${part}" "${MNT}" 2>/dev/null; then
    if [[ -f "${MNT}/EFI/Microsoft/Boot/BCD" ]]; then
      esp="${part}"
      break
    fi
    umount "${MNT}"
  fi
done

[[ -n "${esp}" ]] || { echo "no ESP with EFI/Microsoft/Boot/BCD found" >&2; exit 1; }
echo "ESP: ${esp}"

target="${MNT}/EFI/Microsoft/Boot/BCD"
mkdir -p "${BACKUP_DIR}"
stamp="$(date +%Y%m%d-%H%M%S)"
cp -f "${target}" "${BACKUP_DIR}/BCD.before-${stamp}"
echo "backed up on-disk BCD -> ${BACKUP_DIR}/BCD.before-${stamp}"

cp -f "${BCD}" "${target}" || { echo "copy failed" >&2; exit 1; }
sync

if cmp -s "${BCD}" "${target}"; then
  echo "installed $(stat -c %s "${target}") bytes: ${BCD} -> ESP BCD"
else
  echo "VERIFY FAILED: on-disk BCD differs from source" >&2
  exit 1
fi
