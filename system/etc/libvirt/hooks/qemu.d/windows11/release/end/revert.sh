#!/usr/bin/env bash
# Single-GPU passthrough - VM stop (AMD GPU, Hyprland/LightDM).

set -u

HOOK_LOG_LIB="${HOOK_LOG_LIB:-/etc/libvirt/windows11/hook-log.sh}"
# shellcheck source=/etc/libvirt/windows11/hook-log.sh
[[ -f "${HOOK_LOG_LIB}" ]] && source "${HOOK_LOG_LIB}"
hook_log_begin "release/end/revert.sh" "$@"
hook_log_attach
set -x

export VIRSH_DEFAULT_CONNECT_URI='qemu:///system'
export LC_ALL=C
export LANG=C

ENABLE_FILE="${ENABLE_FILE:-/etc/libvirt/hooks/windows11-gpu-passthrough.enabled}"
if [[ ! -e "${ENABLE_FILE}" ]]; then
  echo "windows11 GPU passthrough hook disabled; create ${ENABLE_FILE} to enable it."
  exit 0
fi

PID_FILE="/run/windows11-watchdog.pid"
if [[ -f "${PID_FILE}" ]]; then
  pid="$(cat "${PID_FILE}" 2>/dev/null || true)"
  [[ -n "${pid}" ]] && kill "${pid}" 2>/dev/null || true
  rm -f "${PID_FILE}"
  echo "STEP: cancelled watchdog pid=${pid:-none}"
fi

GPU_NODE="${GPU_NODE:-pci_0000_03_00_0}"
AUDIO_NODE="${AUDIO_NODE:-pci_0000_03_00_1}"
DISPLAY_MANAGER="${DISPLAY_MANAGER:-display-manager.service}"

bind_vtconsoles() {
  local vt

  shopt -s nullglob
  for vt in /sys/class/vtconsole/vtcon*/bind; do
    echo 1 > "${vt}" 2>/dev/null || true
  done
  shopt -u nullglob
}

bind_efi_framebuffer() {
  local path="/sys/bus/platform/drivers/efi-framebuffer/bind"

  [[ -e "${path}" ]] || return 0
  echo efi-framebuffer.0 > "${path}" 2>/dev/null || true
}

reattach_node() {
  local node="$1"

  echo "STEP: nodedev-reattach ${node}"
  virsh nodedev-reattach "${node}" || true
}

reattach_node "${AUDIO_NODE}"
reattach_node "${GPU_NODE}"

echo "STEP: modprobe amdgpu"
modprobe amdgpu || true
echo "STEP: udevadm settle"
udevadm settle || true
echo "STEP: bind_vtconsoles"
bind_vtconsoles
echo "STEP: bind_efi_framebuffer"
bind_efi_framebuffer
echo "STEP: start ${DISPLAY_MANAGER}"
systemctl start "${DISPLAY_MANAGER}" || true
echo "STEP: release/end complete"
