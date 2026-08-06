#!/usr/bin/env bash
# After QEMU starts, ensure the guest tap is enslaved to br0 (NM-managed bridge).
set -u

_here="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=/dev/null
source "$(cd "${_here}/../../../../.." && pwd)/windows11/paths.sh"
# shellcheck source=/dev/null
[[ -f "${HOOK_LOG_LIB}" ]] && source "${HOOK_LOG_LIB}"

_guest="${1:-${DOMAIN:-windows11}}"
export VIRSH_DEFAULT_CONNECT_URI="${VIRSH_DEFAULT_CONNECT_URI:-qemu:///system}"

# shellcheck source=/dev/null
[[ -f "${GPU_HANDOFF_CONF}" ]] && source "${GPU_HANDOFF_CONF}"
# shellcheck source=/dev/null
source "${BRIDGE_LIB}"

# The config also defines DOMAIN; libvirt's guest name wins.
export DOMAIN="${_guest}"

# libvirt feeds the domain XML on stdin. Read it before the log redirect.
_domain_xml="$(cat)"

hook_log_begin "windows11 started/begin/bridge-ensure.sh" "$@"
hook_log_attach
set -x

_tap="$(printf '%s' "${_domain_xml}" | tap_iface_from_xml "${LAN_BRIDGE:-br0}")"

# libvirt aborts the domain start if this hook fails, so never exit non-zero:
# no LAN uplink is far better than no VM.
if ! bridge_ensure_tap "${_tap}"; then
  echo "WARN: could not attach ${DOMAIN} tap to ${LAN_BRIDGE:-br0}; guest runs without LAN uplink" >&2
fi
exit 0
