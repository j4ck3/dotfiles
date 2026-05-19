#!/usr/bin/env bash
# Single-GPU passthrough - VM start (AMD RX 7900, Intel IOMMU, Hyprland/LightDM).

set -Eeuo pipefail

HOOK_LOG_LIB="${HOOK_LOG_LIB:-/etc/libvirt/windows11/hook-log.sh}"
# shellcheck source=/etc/libvirt/windows11/hook-log.sh
[[ -f "${HOOK_LOG_LIB}" ]] && source "${HOOK_LOG_LIB}"
hook_log_begin "prepare/begin/start.sh" "$@"
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

GPU_NODE="${GPU_NODE:-pci_0000_03_00_0}"
AUDIO_NODE="${AUDIO_NODE:-pci_0000_03_00_1}"
DISPLAY_MANAGER="${DISPLAY_MANAGER:-display-manager.service}"
CONSOLE_USER="${CONSOLE_USER:-jacke}"

bind_vtconsoles() {
  local value="$1" vt
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
  local pattern="$1" i
  for i in {1..60}; do
    pgrep -x "${pattern}" >/dev/null || return 0
    sleep 0.25
  done
  pkill -TERM -x "${pattern}" 2>/dev/null || true
  sleep 1
  pkill -KILL -x "${pattern}" 2>/dev/null || true
}

graceful_stop_hyprland() {
  if ! pgrep -x Hyprland >/dev/null; then
    return 0
  fi
  if command -v hyprctl >/dev/null && id "${CONSOLE_USER}" &>/dev/null; then
    runuser -u "${CONSOLE_USER}" -- hyprctl dispatch exit 2>/dev/null || true
    wait_for_process_exit Hyprland
    sleep 2
  fi
  if pgrep -x Hyprland >/dev/null; then
    local session desktop
    while read -r session _; do
      [[ -n "${session}" ]] || continue
      desktop="$(loginctl show-session "${session}" -p Desktop --value 2>/dev/null || true)"
      [[ "${desktop}" == "hyprland" ]] && loginctl terminate-session "${session}" 2>/dev/null || true
    done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
    wait_for_process_exit Hyprland
    sleep 2
  fi
}

stop_display_stack() {
  graceful_stop_hyprland
  systemctl stop "${DISPLAY_MANAGER}" 2>/dev/null || true
  wait_for_process_exit Hyprland
  wait_for_process_exit Xwayland
  sleep 1
}

rollback() {
  local exit_code=$?
  set +e
  echo "ROLLBACK: hook failed (exit=${exit_code}, line=${BASH_LINENO[0]:-?})"
  virsh nodedev-reattach "${AUDIO_NODE}" 2>/dev/null || true
  virsh nodedev-reattach "${GPU_NODE}" 2>/dev/null || true
  modprobe amdgpu 2>/dev/null || true
  bind_vtconsoles 1
  bind_efi_framebuffer bind
  systemctl start "${DISPLAY_MANAGER}" 2>/dev/null || true
  echo "ROLLBACK: done"
  exit "${exit_code}"
}

trap rollback ERR

echo "STEP: stop_display_stack"
stop_display_stack
echo "STEP: bind_vtconsoles 0"
bind_vtconsoles 0
echo "STEP: bind_efi_framebuffer unbind"
bind_efi_framebuffer unbind
echo "STEP: sleep 3"
sleep 3

echo "STEP: modprobe kvmfr (Looking Glass)"
if [[ -f /dev/kvmfr0 && ! -c /dev/kvmfr0 ]]; then
  echo "WARNING: removing stale /dev/kvmfr0 file before loading kvmfr" >&2
  rm -f /dev/kvmfr0
fi
modprobe kvmfr 2>/dev/null || echo "WARNING: kvmfr not loaded (install looking-glass-module-dkms)" >&2

echo "STEP: modprobe vfio-pci"
modprobe vfio-pci
echo "STEP: nodedev-detach ${GPU_NODE}"
virsh nodedev-detach "${GPU_NODE}"
echo "STEP: nodedev-detach ${AUDIO_NODE}"
virsh nodedev-detach "${AUDIO_NODE}"

trap - ERR

WATCHDOG_SECONDS="${WINDOWS11_WATCHDOG_SECONDS:-900}"
PID_FILE="/run/windows11-watchdog.pid"
rm -f "${PID_FILE}"
if [[ "${WATCHDOG_SECONDS}" =~ ^[0-9]+$ ]] && [[ "${WATCHDOG_SECONDS}" -gt 0 ]]; then
  if [[ -x /usr/local/bin/windows11-watchdog-revert ]]; then
    nohup env DOMAIN=windows11 PID_FILE="${PID_FILE}" \
      bash -c 'sleep "$1"; exec /usr/local/bin/windows11-watchdog-revert' \
      _ "${WATCHDOG_SECONDS}" </dev/null >/dev/null 2>&1 &
  else
    nohup bash -c 'sleep "$1"; virsh destroy windows11 2>/dev/null || true' \
      _ "${WATCHDOG_SECONDS}" </dev/null >/dev/null 2>&1 &
  fi
  watchdog_pid=$!
  disown -h "${watchdog_pid}" 2>/dev/null || disown "${watchdog_pid}" 2>/dev/null || true
  echo "${watchdog_pid}" > "${PID_FILE}"
  echo "STEP: watchdog started pid=${watchdog_pid} seconds=${WATCHDOG_SECONDS}"
else
  echo "STEP: watchdog disabled"
fi

echo "STEP: prepare/begin complete — libvirt may start QEMU now"
