#!/usr/bin/env bash
# VFIO-Tools path: /etc/libvirt/hooks/qemu.d/windows11-stealth/release/end/revert.sh
# Restore host GPU after the stealth clone stops.
set -u

HANDOFF_LIB="${HANDOFF_LIB:-/etc/libvirt/windows11/gpu-handoff.sh}"
# shellcheck source=/etc/libvirt/windows11/gpu-handoff.sh
source "${HANDOFF_LIB}"

export DOMAIN="${DOMAIN:-windows11-stealth}"
export GPU_HANDOFF_FORCE=1

hook_log_begin "windows11-stealth release/end/revert.sh" "$@"
hook_log_attach
set -x

gpu_handoff_release_end
