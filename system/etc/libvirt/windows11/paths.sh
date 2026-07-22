# Shared path resolution for windows11 passthrough (sourced, not executed).
# Always prefers the live files under ~/dotfiles/system — no stow re-run needed.
#
# Usage from a script under system/usr/local/bin (possibly via /usr/local/bin symlink):
#   # shellcheck source=/dev/null
#   source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../../../etc/libvirt/windows11" && pwd)/paths.sh"
#
# Usage from a file already in this directory (gpu-handoff.sh, etc.):
#   # shellcheck source=/dev/null
#   source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/paths.sh"

_windows11_paths_src="$(readlink -f "${BASH_SOURCE[0]}")"
WINDOWS11_DIR="$(cd "$(dirname "${_windows11_paths_src}")" && pwd -P)"
unset _windows11_paths_src

# system/etc/libvirt (XML fragments, resolve-evdev.py, README)
WINDOWS11_LIBVIRT_ETC="$(cd "${WINDOWS11_DIR}/.." && pwd -P)"
# system/etc/libvirt/hooks
WINDOWS11_HOOKS_DIR="$(cd "${WINDOWS11_LIBVIRT_ETC}/hooks" && pwd -P)"
# system/
DOTFILES_SYSTEM="$(cd "${WINDOWS11_LIBVIRT_ETC}/../.." && pwd -P)"
# repo root
DOTFILES_ROOT="$(cd "${DOTFILES_SYSTEM}/.." && pwd -P)"

# Common libs (override via env still works)
HOOK_LOG_LIB="${HOOK_LOG_LIB:-${WINDOWS11_DIR}/hook-log.sh}"
GPU_HANDOFF_LIB="${GPU_HANDOFF_LIB:-${WINDOWS11_DIR}/gpu-handoff.sh}"
GPU_HANDOFF_CONF="${GPU_HANDOFF_CONF:-${WINDOWS11_DIR}/gpu-handoff.conf}"
BRIDGE_LIB="${BRIDGE_LIB:-${WINDOWS11_DIR}/bridge-ensure.sh}"
PATCH_DOMAIN_PY="${PATCH_DOMAIN_PY:-${WINDOWS11_DIR}/patch-domain.py}"

# Libvirt requires this marker under /etc (created by windows11-mode passthrough).
ENABLE_FILE="${ENABLE_FILE:-/etc/libvirt/hooks/windows11-gpu-passthrough.enabled}"
