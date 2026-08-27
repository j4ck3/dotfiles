#!/usr/bin/env bash
# VFIO-Tools path: qemu.d/windows11-stealth/release/end/revert.sh
# Post-VM (shutdown): peel vfio, queue async GPU restore, start ly.
# Heavy amdgpu probe lives in windows11-restore-display — NOT here.
set -u

_here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$(cd "${_here}/../../../../.." && pwd)/windows11/paths.sh"
# shellcheck source=/dev/null
source "${GPU_HANDOFF_LIB}"

export DOMAIN="${DOMAIN:-windows11-stealth}"
export GPU_HANDOFF_FORCE="${GPU_HANDOFF_FORCE:-1}"
# Libvirt pipes XML; manual force-stop/revert has a TTY — never block on cat.
read_hook_domain_xml

hook_log_begin "windows11-stealth release/end/revert.sh" "$@"
hook_log_attach
set -x

gpu_handoff_release_end

# Belt-and-suspenders: release_end already starts ly + queues restore.
if ! systemctl is-active --quiet ly@tty1.service 2>/dev/null; then
  echo "STEP: post-VM start ly@tty1"
  start_ly_units
fi
safe_chvt 1 || true
