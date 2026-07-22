#!/usr/bin/env bash
# VFIO-Tools path: qemu.d/windows11/release/end/revert.sh
# Single-GPU passthrough — reattach RX 7900, restart Hyprland session.
set -u

_here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$(cd "${_here}/../../../../.." && pwd)/windows11/paths.sh"
# shellcheck source=/dev/null
source "${GPU_HANDOFF_LIB}"

export GPU_HANDOFF_FORCE=1

hook_log_begin "release/end/revert.sh" "$@"
hook_log_attach
set -x

gpu_handoff_release_end
