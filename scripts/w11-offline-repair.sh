#!/usr/bin/env bash
# Restore the boot-critical driver services that stealth hardening deleted from
# the windows11-stealth guest: volume, vdrvroot, msisadrv, isapnp.
#
# Without the "volume" service the STORAGE\Volume device nodes cannot start, so
# the kernel cannot mount the boot volume and bugchecks 0x7B.
#
# Safety: takes a qcow2 snapshot first, backs up the original hive, and verifies
# the replacement hive parses before writing. Donor image is mounted read-only.
#
#   sudo bash scripts/w11-offline-repair.sh
set -uo pipefail

STEALTH="${STEALTH:-/home/jacke/.local/share/libvirt/images/windows11-stealth.qcow2}"
DONOR="${DONOR:-/home/jacke/.local/share/libvirt/images/windows11.qcow2}"
REPAIRED_HIVE="${REPAIRED_HIVE:-/tmp/SYSTEM.repaired}"
BACKUP_DIR="${BACKUP_DIR:-/home/jacke/.cache/windows11-stealth-debug}"
SNAPSHOT="${SNAPSHOT:-pre-volume-repair}"
OWNER="${OWNER:-jacke}"
DRIVERS=(volume.sys vdrvroot.sys msisadrv.sys isapnp.sys)

STAGE="$(mktemp -d)"
MNT="$(mktemp -d)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "must run as root: sudo bash $0" >&2
  exit 1
fi

for dom in windows11-stealth windows11; do
  if [[ "$(virsh -c qemu:///system domstate "${dom}" 2>/dev/null)" == "running" ]]; then
    echo "${dom} is running. Stop it first." >&2
    exit 1
  fi
done

if [[ ! -s "${REPAIRED_HIVE}" ]]; then
  echo "repaired hive ${REPAIRED_HIVE} missing" >&2
  exit 1
fi

cleanup() {
  mountpoint -q "${MNT}" && umount "${MNT}"
  qemu-nbd --disconnect /dev/nbd0 >/dev/null 2>&1
  qemu-nbd --disconnect /dev/nbd1 >/dev/null 2>&1
  rmdir "${MNT}" "${STAGE}" 2>/dev/null
}
trap cleanup EXIT

modprobe nbd max_part=16

echo "== staging donor drivers (read-only) =="
qemu-nbd --read-only --connect=/dev/nbd1 "${DONOR}" || exit 1
sleep 2
partx -u /dev/nbd1 >/dev/null 2>&1
staged=0
for part in /dev/nbd1p*; do
  [[ -b "${part}" ]] || continue
  if mount -t ntfs3 -o ro "${part}" "${MNT}" 2>/dev/null; then
    if [[ -d "${MNT}/Windows/System32/drivers" ]]; then
      for drv in "${DRIVERS[@]}"; do
        if cp -f "${MNT}/Windows/System32/drivers/${drv}" "${STAGE}/${drv}" 2>/dev/null; then
          echo "  staged ${drv} ($(stat -c %s "${STAGE}/${drv}") bytes)"
          staged=$((staged + 1))
        else
          echo "  MISSING in donor: ${drv}"
        fi
      done
      umount "${MNT}"
      break
    fi
    umount "${MNT}"
  fi
done
qemu-nbd --disconnect /dev/nbd1 >/dev/null 2>&1

if [[ "${staged}" -ne "${#DRIVERS[@]}" ]]; then
  echo "only staged ${staged}/${#DRIVERS[@]} drivers; aborting" >&2
  exit 1
fi

echo
echo "== snapshotting ${SNAPSHOT} (rollback point) =="
qemu-img snapshot -c "${SNAPSHOT}" "${STEALTH}" && echo "  snapshot created"
qemu-img snapshot -l "${STEALTH}"

echo
echo "== applying repair to stealth image (read-write) =="
qemu-nbd --connect=/dev/nbd0 "${STEALTH}" || exit 1
sleep 2
partx -u /dev/nbd0 >/dev/null 2>&1

win_part=""
for part in /dev/nbd0p*; do
  [[ -b "${part}" ]] || continue
  if mount -t ntfs3 -o ro "${part}" "${MNT}" 2>/dev/null; then
    if [[ -d "${MNT}/Windows/System32/config" ]]; then
      win_part="${part}"
      umount "${MNT}"
      break
    fi
    umount "${MNT}"
  fi
done

if [[ -z "${win_part}" ]]; then
  echo "windows volume not found" >&2
  exit 1
fi

mount -t ntfs3 -o rw "${win_part}" "${MNT}" || {
  echo "read-write mount of ${win_part} failed" >&2
  exit 1
}

mkdir -p "${BACKUP_DIR}"
stamp="$(date +%Y%m%d-%H%M%S)"
cp -f "${MNT}/Windows/System32/config/SYSTEM" "${BACKUP_DIR}/SYSTEM.pre-repair.${stamp}"
cp -f "${MNT}/Windows/System32/config/SYSTEM.LOG1" "${BACKUP_DIR}/SYSTEM.LOG1.pre-repair.${stamp}" 2>/dev/null
echo "  backed up original hive to ${BACKUP_DIR}/SYSTEM.pre-repair.${stamp}"

for drv in "${DRIVERS[@]}"; do
  cp -f "${STAGE}/${drv}" "${MNT}/Windows/System32/drivers/${drv}"
  echo "  installed drivers/${drv}"
done

cp -f "${REPAIRED_HIVE}" "${MNT}/Windows/System32/config/SYSTEM"
echo "  installed repaired SYSTEM hive"

sync
echo
echo "== verifying on-disk result =="
for drv in "${DRIVERS[@]}"; do
  path="${MNT}/Windows/System32/drivers/${drv}"
  [[ -f "${path}" ]] && printf '  %-16s %s bytes\n' "${drv}" "$(stat -c %s "${path}")"
done
cmp -s "${REPAIRED_HIVE}" "${MNT}/Windows/System32/config/SYSTEM" \
  && echo "  SYSTEM hive matches repaired copy" \
  || echo "  WARNING: hive mismatch after write"

umount "${MNT}"
chown -R "${OWNER}:${OWNER}" "${BACKUP_DIR}" 2>/dev/null

echo
echo "repair complete. rollback if needed:"
echo "  sudo qemu-img snapshot -a ${SNAPSHOT} ${STEALTH}"
