#!/usr/bin/env bash
# Single-GPU passthrough - VM start (AMD GPU, Intel IOMMU, Hyprland/LightDM).
# Install: e.g. sudo cp -a .../qemu.d/windows11 /etc/libvirt/hooks/qemu.d/windows11
# For dynamic handoff, remove vfio-pci.ids= from kernel cmdline so amdgpu owns the GPU until detach.

set -Eeuo pipefail
set -x

# Hooks must use the system libvirt daemon (same as `virsh -c qemu:///system`).
export VIRSH_DEFAULT_CONNECT_URI='qemu:///system'

ENABLE_FILE="${ENABLE_FILE:-/etc/libvirt/hooks/windows11-gpu-passthrough.enabled}"
if [[ ! -e "${ENABLE_FILE}" ]]; then
  echo "windows11 GPU passthrough hook disabled; create ${ENABLE_FILE} to enable it."
  exit 0
fi

# PCI from: lspci | grep -E 'VGA|Audio' -> 03:00.0 -> pci_0000_03_00_0
GPU_NODE="${GPU_NODE:-pci_0000_03_00_0}"
AUDIO_NODE="${AUDIO_NODE:-pci_0000_03_00_1}"
DISPLAY_MANAGER="${DISPLAY_MANAGER:-display-manager.service}"

bind_vtconsoles() {
  local value="$1"
  local vt

  shopt -s nullglob
  for vt in /sys/class/vtconsole/vtcon*/bind; do
    echo "${value}" > "${vt}" 2>/dev/null || true
  done
  shopt -u nullglob
}

bind_efi_framebuffer() {
  local action="$1"
  local path="/sys/bus/platform/drivers/efi-framebuffer/${action}"

  [[ -e "${path}" ]] || return 0
  echo efi-framebuffer.0 > "${path}" 2>/dev/null || true
}

wait_for_process_exit() {
  local pattern="$1"
  local i

  for i in {1..40}; do
    pgrep -x "${pattern}" >/dev/null || return 0
    sleep 0.25
  done

  pkill -TERM -x "${pattern}" 2>/dev/null || true
  sleep 1
  pkill -KILL -x "${pattern}" 2>/dev/null || true
}

stop_hyprland_sessions() {
  local session desktop service

  while read -r session _; do
    [[ -n "${session}" ]] || continue

    desktop="$(loginctl show-session "${session}" -p Desktop --value 2>/dev/null || true)"
    service="$(loginctl show-session "${session}" -p Service --value 2>/dev/null || true)"

    if [[ "${desktop}" == "hyprland" || "${service}" == "lightdm" ]]; then
      loginctl terminate-session "${session}" 2>/dev/null || true
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)

  systemctl stop "${DISPLAY_MANAGER}"
  wait_for_process_exit Hyprland
  wait_for_process_exit Xwayland
}

rollback() {
  local exit_code=$?

  set +e
  virsh nodedev-reattach "${AUDIO_NODE}"
  virsh nodedev-reattach "${GPU_NODE}"
  modprobe amdgpu
  bind_vtconsoles 1
  bind_efi_framebuffer bind
  systemctl start "${DISPLAY_MANAGER}"

  exit "${exit_code}"
}

trap rollback ERR

stop_hyprland_sessions
bind_vtconsoles 0
bind_efi_framebuffer unbind
sleep 2

modprobe vfio-pci
virsh nodedev-detach "${GPU_NODE}"
virsh nodedev-detach "${AUDIO_NODE}"

trap - ERR
