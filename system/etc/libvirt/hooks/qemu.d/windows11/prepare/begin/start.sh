#!/usr/bin/env bash
# VFIO-Tools path: qemu.d/windows11/prepare/begin/start.sh
# Single-GPU passthrough prepare hook.
set -Eeuo pipefail

_here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$(cd "${_here}/../../../../.." && pwd)/windows11/paths.sh"
# shellcheck source=/dev/null
source "${GPU_HANDOFF_LIB}"

export DOMAIN="${DOMAIN:-windows11}"

hook_log_begin "windows11 prepare/begin/start.sh" "$@"
hook_log_attach
set -x

trap gpu_handoff_rollback ERR
gpu_handoff_prepare_begin
trap - ERR
