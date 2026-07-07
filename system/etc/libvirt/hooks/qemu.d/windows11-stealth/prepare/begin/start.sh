#!/usr/bin/env bash
# VFIO-Tools path: /etc/libvirt/hooks/qemu.d/windows11-stealth/prepare/begin/start.sh
# Single-GPU passthrough for the stealth clone.
set -Eeuo pipefail

HANDOFF_LIB="${HANDOFF_LIB:-/etc/libvirt/windows11/gpu-handoff.sh}"
# shellcheck source=/etc/libvirt/windows11/gpu-handoff.sh
source "${HANDOFF_LIB}"

export DOMAIN="windows11-stealth"

hook_log_begin "windows11-stealth prepare/begin/start.sh" "$@"
hook_log_attach
set -x

trap gpu_handoff_rollback ERR
gpu_handoff_prepare_begin
trap - ERR
