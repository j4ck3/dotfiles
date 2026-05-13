#!/usr/bin/env bash
# Single-GPU passthrough - VM stop (AMD GPU, Hyprland/LightDM).

set -u
set -x

export VIRSH_DEFAULT_CONNECT_URI='qemu:///system'

ENABLE_FILE="${ENABLE_FILE:-/etc/libvirt/hooks/windows11-gpu-passthrough.enabled}"
if [[ ! -e "${ENABLE_FILE}" ]]; then
  echo "windows11 GPU passthrough hook disabled; create ${ENABLE_FILE} to enable it."
  exit 0
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

  virsh nodedev-reattach "${node}" || true
}

# Audio first, then GPU. Keep going even if libvirt says a device is already attached.
reattach_node "${AUDIO_NODE}"
reattach_node "${GPU_NODE}"

modprobe amdgpu || true
udevadm settle || true
bind_vtconsoles
bind_efi_framebuffer
systemctl start "${DISPLAY_MANAGER}" || true
