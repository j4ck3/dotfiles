#!/usr/bin/env bash
# Read-only offline extraction of boot-relevant artifacts from the stealth VM disk.
# Requires root (nbd + mount). The guest disk is never written to.
#
#   sudo bash scripts/w11-offline-extract.sh
set -uo pipefail

IMAGE="${IMAGE:-/home/jacke/.local/share/libvirt/images/windows11-stealth.qcow2}"
DOMAIN="${DOMAIN:-windows11-stealth}"
OUT="${OUT:-/tmp/w11diag}"
OWNER="${OWNER:-jacke}"
NBD="${NBD:-/dev/nbd0}"
MNT="$(mktemp -d)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "must run as root: sudo bash $0" >&2
  exit 1
fi

state="$(virsh -c qemu:///system domstate "${DOMAIN}" 2>/dev/null)"
if [[ "${state}" == "running" ]]; then
  echo "${DOMAIN} is running. Stop it first." >&2
  exit 1
fi

cleanup() {
  mountpoint -q "${MNT}" && umount "${MNT}"
  qemu-nbd --disconnect "${NBD}" >/dev/null 2>&1
  rmdir "${MNT}" 2>/dev/null
}
trap cleanup EXIT

mkdir -p "${OUT}"

echo "== qemu-img check =="
qemu-img check "${IMAGE}" 2>&1 | tee "${OUT}/qemu-img-check.txt"

modprobe nbd max_part=16
qemu-nbd --read-only --connect="${NBD}" "${IMAGE}" || { echo "nbd connect failed" >&2; exit 1; }
sleep 2
partx -u "${NBD}" >/dev/null 2>&1

echo
echo "== partitions =="
lsblk -o NAME,SIZE,FSTYPE,LABEL,PARTTYPENAME "${NBD}" 2>&1 | tee "${OUT}/partitions.txt"

win_part=""
esp_part=""
for part in "${NBD}"p*; do
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

for part in "${NBD}"p*; do
  [[ -b "${part}" ]] || continue
  if mount -t vfat -o ro "${part}" "${MNT}" 2>/dev/null; then
    if [[ -d "${MNT}/EFI/Microsoft/Boot" ]]; then
      esp_part="${part}"
      mkdir -p "${OUT}/esp"
      cp -f "${MNT}/EFI/Microsoft/Boot/BCD" "${OUT}/esp/BCD" 2>/dev/null
    fi
    umount "${MNT}"
    [[ -n "${esp_part}" ]] && break
  fi
done

if [[ -z "${win_part}" ]]; then
  echo "no NTFS partition containing \\Windows\\System32\\config found" >&2
  exit 1
fi

echo
echo "== windows volume: ${win_part} (esp: ${esp_part:-none}) =="
mount -t ntfs3 -o ro "${win_part}" "${MNT}" || { echo "mount failed" >&2; exit 1; }

mkdir -p "${OUT}/hives" "${OUT}/logs"

for hive in SYSTEM SYSTEM.LOG1 SYSTEM.LOG2; do
  cp -f "${MNT}/Windows/System32/config/${hive}" "${OUT}/hives/${hive}" 2>/dev/null \
    && echo "copied hive ${hive}"
done

regback="${MNT}/Windows/System32/config/RegBack/SYSTEM"
if [[ -s "${regback}" ]]; then
  cp -f "${regback}" "${OUT}/hives/SYSTEM.regback"
  echo "copied RegBack SYSTEM ($(stat -c %s "${regback}") bytes)"
else
  echo "RegBack SYSTEM: absent or zero-length (normal on Win10+)"
fi

restore_dir="${MNT}/System Volume Information"
if [[ -d "${restore_dir}" ]]; then
  find "${restore_dir}" -maxdepth 2 -iname '*RP*' -o -maxdepth 2 -iname '_restore*' 2>/dev/null \
    | head -20 > "${OUT}/restore-points.txt"
  echo "restore point candidates: $(wc -l < "${OUT}/restore-points.txt")"
fi

cp -f "${MNT}/Windows/System32/LogFiles/Srt/SrtTrail.txt" "${OUT}/logs/SrtTrail.txt" 2>/dev/null \
  && echo "copied SrtTrail.txt"
cp -f "${MNT}/Windows/ntbtlog.txt" "${OUT}/logs/ntbtlog.txt" 2>/dev/null \
  && echo "copied ntbtlog.txt"
tail -n 3000 "${MNT}/Windows/INF/setupapi.dev.log" > "${OUT}/logs/setupapi.dev.tail.log" 2>/dev/null \
  && echo "copied setupapi tail"

echo
echo "== boot-critical storage drivers ==" | tee "${OUT}/drivers.txt"
for drv in storahci.sys stornvme.sys viostor.sys vioscsi.sys storport.sys disk.sys \
           partmgr.sys volmgr.sys volsnap.sys iastorac.sys iastorvd.sys; do
  path="${MNT}/Windows/System32/drivers/${drv}"
  if [[ -f "${path}" ]]; then
    printf '%-16s %s bytes\n' "${drv}" "$(stat -c %s "${path}")"
  else
    printf '%-16s MISSING\n' "${drv}"
  fi
done | tee -a "${OUT}/drivers.txt"

echo
echo "== upper/lower filter drivers present ==" | tee "${OUT}/filters.txt"
ls -la "${MNT}/Windows/System32/drivers/" 2>/dev/null \
  | awk '$NF ~ /\.sys$/ {print $5, $NF}' | sort -k2 > "${OUT}/driver-listing.txt"
wc -l < "${OUT}/driver-listing.txt" | xargs echo "total .sys files:"

chown -R "${OWNER}:${OWNER}" "${OUT}"
echo
echo "artifacts written to ${OUT}"
