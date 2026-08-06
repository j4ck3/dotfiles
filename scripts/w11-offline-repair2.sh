#!/usr/bin/env bash
# Second-pass repair: keep only the boot-critical services that are actually
# needed (volume, vdrvroot) and drop msisadrv/isapnp, which winload rejected
# with 0xc000007b (STATUS_INVALID_IMAGE_FORMAT).
#
# Also compares each staged driver against the donor by checksum, so we learn
# whether the rejection was a bad copy or something about the file itself.
#
#   sudo bash scripts/w11-offline-repair2.sh
set -uo pipefail

STEALTH="${STEALTH:-/home/jacke/.local/share/libvirt/images/windows11-stealth.qcow2}"
DONOR="${DONOR:-/home/jacke/.local/share/libvirt/images/windows11.qcow2}"
REPAIRED_HIVE="${REPAIRED_HIVE:-/tmp/SYSTEM.repaired2}"
BACKUP_DIR="${BACKUP_DIR:-/home/jacke/.cache/windows11-stealth-debug}"
REPORT="${REPORT:-/tmp/w11repair2-report.txt}"
OWNER="${OWNER:-jacke}"

KEEP=(volume.sys vdrvroot.sys)
DROP=(msisadrv.sys isapnp.sys)
ALL=("${KEEP[@]}" "${DROP[@]}")

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

[[ -s "${REPAIRED_HIVE}" ]] || { echo "missing ${REPAIRED_HIVE}" >&2; exit 1; }

cleanup() {
  mountpoint -q "${MNT}" && umount "${MNT}"
  qemu-nbd --disconnect /dev/nbd0 >/dev/null 2>&1
  qemu-nbd --disconnect /dev/nbd1 >/dev/null 2>&1
  rmdir "${MNT}" "${STAGE}" 2>/dev/null
}
trap cleanup EXIT

: > "${REPORT}"
modprobe nbd max_part=16

find_win_volume() {
  local dev="$1" opts="$2" part
  for part in "${dev}"p*; do
    [[ -b "${part}" ]] || continue
    if mount -t ntfs3 -o "${opts}" "${part}" "${MNT}" 2>/dev/null; then
      [[ -d "${MNT}/Windows/System32/config" ]] && { echo "${part}"; return 0; }
      umount "${MNT}"
    fi
  done
  return 1
}

echo "== staging donor drivers (read-only) ==" | tee -a "${REPORT}"
qemu-nbd --read-only --connect=/dev/nbd1 "${DONOR}" || exit 1
sleep 2
partx -u /dev/nbd1 >/dev/null 2>&1
if ! find_win_volume /dev/nbd1 ro >/dev/null; then
  echo "donor windows volume not found" >&2
  exit 1
fi
for drv in "${ALL[@]}"; do
  if cp -f "${MNT}/Windows/System32/drivers/${drv}" "${STAGE}/${drv}" 2>/dev/null; then
    printf '  donor   %-16s %10s bytes  %s\n' "${drv}" \
      "$(stat -c %s "${STAGE}/${drv}")" "$(sha256sum "${STAGE}/${drv}" | cut -c1-16)" \
      | tee -a "${REPORT}"
  else
    echo "  donor   ${drv} MISSING" | tee -a "${REPORT}"
  fi
done
umount "${MNT}"
qemu-nbd --disconnect /dev/nbd1 >/dev/null 2>&1

echo | tee -a "${REPORT}"
echo "== inspecting current stealth image ==" | tee -a "${REPORT}"
qemu-nbd --connect=/dev/nbd0 "${STEALTH}" || exit 1
sleep 2
partx -u /dev/nbd0 >/dev/null 2>&1
win_part="$(find_win_volume /dev/nbd0 ro)" || { echo "windows volume not found" >&2; exit 1; }
for drv in "${ALL[@]}"; do
  path="${MNT}/Windows/System32/drivers/${drv}"
  if [[ -f "${path}" ]]; then
    magic="$(head -c2 "${path}" | tr -d '\0')"
    printf '  stealth %-16s %10s bytes  %s  magic=%s\n' "${drv}" \
      "$(stat -c %s "${path}")" "$(sha256sum "${path}" | cut -c1-16)" "${magic}" \
      | tee -a "${REPORT}"
  else
    echo "  stealth ${drv} absent" | tee -a "${REPORT}"
  fi
done
umount "${MNT}"

echo | tee -a "${REPORT}"
echo "== applying second-pass repair ==" | tee -a "${REPORT}"
mount -t ntfs3 -o rw "${win_part}" "${MNT}" || { echo "rw mount failed" >&2; exit 1; }

stamp="$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"
cp -f "${MNT}/Windows/System32/config/SYSTEM" "${BACKUP_DIR}/SYSTEM.pass1.${stamp}"

for drv in "${KEEP[@]}"; do
  cp -f "${STAGE}/${drv}" "${MNT}/Windows/System32/drivers/${drv}"
  echo "  ensured drivers/${drv}" | tee -a "${REPORT}"
done

for drv in "${DROP[@]}"; do
  if rm -f "${MNT}/Windows/System32/drivers/${drv}" 2>/dev/null; then
    echo "  removed drivers/${drv} (service key also dropped)" | tee -a "${REPORT}"
  fi
done

cp -f "${REPAIRED_HIVE}" "${MNT}/Windows/System32/config/SYSTEM"
sync
cmp -s "${REPAIRED_HIVE}" "${MNT}/Windows/System32/config/SYSTEM" \
  && echo "  SYSTEM hive installed and verified" | tee -a "${REPORT}" \
  || echo "  WARNING: hive mismatch" | tee -a "${REPORT}"

umount "${MNT}"
chown -R "${OWNER}:${OWNER}" "${BACKUP_DIR}" 2>/dev/null
chown "${OWNER}:${OWNER}" "${REPORT}" 2>/dev/null

echo
echo "done. report: ${REPORT}"
