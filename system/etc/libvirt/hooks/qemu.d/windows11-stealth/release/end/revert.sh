#!/usr/bin/env bash
# VFIO-Tools path: qemu.d/windows11-stealth/release/end/revert.sh
# Restore host GPU after the stealth clone stops.
set -u

_here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$(cd "${_here}/../../../../.." && pwd)/windows11/paths.sh"
# shellcheck source=/dev/null
source "${GPU_HANDOFF_LIB}"

export DOMAIN="${DOMAIN:-windows11-stealth}"
export GPU_HANDOFF_FORCE=1

hook_log_begin "windows11-stealth release/end/revert.sh" "$@"
hook_log_attach
set -x

gpu_handoff_release_end
