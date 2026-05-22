#!/usr/bin/env bash
# VFIO-Tools path: /etc/libvirt/hooks/qemu.d/windows11/release/end/revert.sh
# Single-GPU passthrough — reattach RX 7900, restart Hyprland session.
set -u

HANDOFF_LIB="${HANDOFF_LIB:-/etc/libvirt/windows11/gpu-handoff.sh}"
# shellcheck source=/etc/libvirt/windows11/gpu-handoff.sh
source "${HANDOFF_LIB}"

hook_log_begin "release/end/revert.sh" "$@"
hook_log_attach
set -x

gpu_handoff_release_end
