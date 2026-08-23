#!/usr/bin/env bash
# Apply the recommended snapper "root" config for the HTPC.
#
# Tuned for a small (~46 GiB) btrfs single disk with snap-pac creating a
# pre/post pair on every pacman operation:
#   - NUMBER_LIMIT=10 / NUMBER_LIMIT_IMPORTANT=5  (keep snapshot count sane)
#   - btrfs quota enabled + QGROUP=1/0            (make SPACE_LIMIT/FREE_LIMIT
#                                                  space-aware cleanup actually
#                                                  enforce)
#   - timeline snapshots disabled                 (snap-pac already covers
#                                                  update-based snapshots)
#
# This intentionally does NOT overwrite /etc/snapper/configs/root wholesale
# (that file carries install-specific values). It enables quota and applies the
# tuned keys idempotently via snapper, which is safe to re-run.
set -euo pipefail

CONFIG="${SNAPPER_CONFIG:-root}"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if ! command -v snapper >/dev/null 2>&1; then
  echo "snapper is not installed" >&2
  exit 1
fi

if ! snapper list-configs | awk '{print $1}' | grep -qx "${CONFIG}"; then
  echo "snapper config '${CONFIG}' does not exist; create it first " \
       "(e.g. 'snapper -c ${CONFIG} create-config /')" >&2
  exit 1
fi

echo "Enabling btrfs quota for space-aware cleanup..."
snapper -c "${CONFIG}" setup-quota || true

echo "Applying tuned snapper limits to config '${CONFIG}'..."
snapper -c "${CONFIG}" set-config \
  NUMBER_CLEANUP="yes" \
  NUMBER_MIN_AGE="1800" \
  NUMBER_LIMIT="10" \
  NUMBER_LIMIT_IMPORTANT="5" \
  TIMELINE_CREATE="no" \
  TIMELINE_CLEANUP="yes" \
  EMPTY_PRE_POST_CLEANUP="yes" \
  SPACE_LIMIT="0.5" \
  FREE_LIMIT="0.2"

echo "Ensuring snapper-cleanup.timer is enabled..."
systemctl enable --now snapper-cleanup.timer || true

echo "Done. Current values:"
grep -E 'NUMBER_LIMIT|NUMBER_LIMIT_IMPORTANT|QGROUP|SPACE_LIMIT|FREE_LIMIT|TIMELINE_CREATE' \
  "/etc/snapper/configs/${CONFIG}"
