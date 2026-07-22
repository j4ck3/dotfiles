#!/usr/bin/env bash
# After QEMU starts, ensure the guest tap is enslaved to br0 (NM-managed bridge).
set -u

_here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$(cd "${_here}/../../../../.." && pwd)/windows11/paths.sh"
# shellcheck source=/dev/null
[[ -f "${HOOK_LOG_LIB}" ]] && source "${HOOK_LOG_LIB}"

export DOMAIN="${DOMAIN:-windows11}"
export VIRSH_DEFAULT_CONNECT_URI="${VIRSH_DEFAULT_CONNECT_URI:-qemu:///system}"

# shellcheck source=/dev/null
[[ -f "${GPU_HANDOFF_CONF}" ]] && source "${GPU_HANDOFF_CONF}"
# shellcheck source=/dev/null
source "${BRIDGE_LIB}"

hook_log_begin "windows11 started/begin/bridge-ensure.sh" "$@"
hook_log_attach
set -x

sleep 1
bridge_ensure_for_domain "${DOMAIN}"
