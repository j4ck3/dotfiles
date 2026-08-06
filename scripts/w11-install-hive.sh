#!/usr/bin/env bash
# Install a prepared SYSTEM hive into the stealth guest image.
#
# Verifies the on-disk hive still matches what the replacement was built from,
# so a hive modified by the guest since extraction is never silently clobbered.
#
#   sudo HIVE=/tmp/SYSTEM.repaired3 EXPECT=/tmp/SYSTEM.repaired2 \
#        bash scripts/w11-install-hive.sh
set -uo pipefail

STEALTH="${STEALTH:-/home/jacke/.local/share/libvirt/images/windows11-stealth.qcow2}"
HIVE="${HIVE:-/tmp/SYSTEM.repaired3}"
EXPECT="${EXPECT:-}"
BACKUP_DIR="${BACKUP_DIR:-/home/jacke/.cache/windows11-stealth-debug}"
OWNER="${OWNER:-jacke}"
MNT="$(mktemp -d)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "must run as root: sudo bash $0" >&2
  exit 1
fi

[[ -s "${HIVE}" ]] || { echo "missing hive ${HIVE}" >&2; exit 1; }

if [[ "$(virsh -c qemu:///system domstate windows11-stealth 2>/dev/null)" == "running" ]]; then
  echo "windows11-stealth is running. Stop it first." >&2
  exit 1
fi

cleanup() {
  mountpoint -q "${MNT}" && umount "${MNT}"
  qemu-nbd --disconnect /dev/nbd0 >/dev/null 2>&1
  rmdir "${MNT}" 2>/dev/null
}
trap cleanup EXIT

modprobe nbd max_part=16
qemu-nbd --connect=/dev/nbd0 "${STEALTH}" || exit 1
sleep 2
partx -u /dev/nbd0 >/dev/null 2>&1

win_part=""
for part in /dev/nbd0p*; do
  [[ -b "${part}" ]] || continue
  if mount -t ntfs3 -o ro "${part}" "${MNT}" 2>/dev/null; then
    [[ -d "${MNT}/Windows/System32/config" ]] && { win_part="${part}"; umount "${MNT}"; break; }
    umount "${MNT}"
  fi
done
[[ -n "${win_part}" ]] || { echo "windows volume not found" >&2; exit 1; }

mount -t ntfs3 -o rw "${win_part}" "${MNT}" || { echo "rw mount failed" >&2; exit 1; }
target="${MNT}/Windows/System32/config/SYSTEM"

if [[ -n "${EXPECT}" ]]; then
  if cmp -s "${EXPECT}" "${target}"; then
    echo "on-disk hive matches expected baseline"
  else
    echo "REFUSING: on-disk hive differs from ${EXPECT}" >&2
    echo "the guest modified it since extraction; re-extract and rebuild" >&2
    exit 1
  fi
fi

stamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"
cp -f "${target}" "${BACKUP_DIR}/SYSTEM.before-$(basename "${HIVE}").${stamp}"
cp -f "${HIVE}" "${target}"
sync

if cmp -s "${HIVE}" "${target}"; then
  echo "installed $(basename "${HIVE}") ($(stat -c %s "${target}") bytes)"
else
  echo "WARNING: verification mismatch after write" >&2
fi

umount "${MNT}"
chown -R "${OWNER}:${OWNER}" "${BACKUP_DIR}" 2>/dev/null
echo "done"
