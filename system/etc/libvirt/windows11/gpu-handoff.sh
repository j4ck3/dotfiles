# Shared single-GPU handoff for windows11 (sourced by libvirt hooks).
# Pattern: VFIO-Tools qemu.d + joeknock90 Single-GPU-Passthrough + Hyprland stop.
set -o pipefail

HOOK_LOG_LIB="${HOOK_LOG_LIB:-/etc/libvirt/windows11/hook-log.sh}"
# shellcheck source=/etc/libvirt/windows11/hook-log.sh
[[ -f "${HOOK_LOG_LIB}" ]] && source "${HOOK_LOG_LIB}"

CONF="${GPU_HANDOFF_CONF:-/etc/libvirt/windows11/gpu-handoff.conf}"
if [[ -f "${CONF}" ]]; then
  # shellcheck source=/etc/libvirt/windows11/gpu-handoff.conf
  source "${CONF}"
fi

export VIRSH_DEFAULT_CONNECT_URI="${VIRSH_DEFAULT_CONNECT_URI:-qemu:///system}"
export LC_ALL=C
export LANG=C

DOMAIN="${DOMAIN:-windows11}"
GPU_NODE="${GPU_NODE:-pci_0000_03_00_0}"
AUDIO_NODE="${AUDIO_NODE:-pci_0000_03_00_1}"
GPU_PCI="${GPU_PCI:-0000:03:00.0}"
AUDIO_PCI="${AUDIO_PCI:-0000:03:00.1}"
DISPLAY_MANAGER="${DISPLAY_MANAGER:-display-manager.service}"
CONSOLE_USER="${CONSOLE_USER:-jacke}"
DETACH_SLEEP="${DETACH_SLEEP:-3}"
SKIP_EFI_FB="${SKIP_EFI_FB:-0}"
UNLOAD_AMGPU="${UNLOAD_AMGPU:-1}"
# Max seconds to wait for compositor processes after stopping the display manager.
DISPLAY_STOP_TIMEOUT="${DISPLAY_STOP_TIMEOUT:-12}"
ENABLE_FILE="${ENABLE_FILE:-/etc/libvirt/hooks/windows11-gpu-passthrough.enabled}"

passthrough_enabled() {
  [[ -e "${ENABLE_FILE}" ]]
}

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
  [[ "${SKIP_EFI_FB}" == "1" ]] && return 0
  local path="/sys/bus/platform/drivers/efi-framebuffer/${action}"
  [[ -e "${path}" ]] || return 0
  echo efi-framebuffer.0 > "${path}" 2>/dev/null || true
}

wait_for_process_exit() {
  local pattern="$1" max="${2:-20}" i
  for ((i = 1; i <= max; i++)); do
    pgrep -x "${pattern}" >/dev/null || return 0
    sleep 0.25
  done
  echo "STEP: sending SIGTERM to ${pattern}"
  pkill -TERM -x "${pattern}" 2>/dev/null || true
  sleep 1
  pkill -KILL -x "${pattern}" 2>/dev/null || true
}

hyprland_instance_signature() {
  local uid runtime
  uid="$(id -u "${CONSOLE_USER}" 2>/dev/null)" || return 1
  runtime="/run/user/${uid}"
  [[ -d "${runtime}/hypr" ]] || return 1
  find "${runtime}/hypr" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | head -n1
}

hyprctl_as_user() {
  local sig runtime uid
  command -v hyprctl >/dev/null || return 1
  id "${CONSOLE_USER}" &>/dev/null || return 1
  uid="$(id -u "${CONSOLE_USER}")"
  runtime="/run/user/${uid}"
  sig="$(hyprland_instance_signature)" || return 1
  runuser -u "${CONSOLE_USER}" -- env \
    XDG_RUNTIME_DIR="${runtime}" \
    HYPRLAND_INSTANCE_SIGNATURE="${sig}" \
    hyprctl "$@"
}

# End only the local graphical seat (seat0 etc.), not SSH (Remote=yes).
terminate_graphical_sessions() {
  local session user seat typ remote
  while read -r session _ user _; do
    [[ "${user}" == "${CONSOLE_USER}" ]] || continue
    remote="$(loginctl show-session "${session}" -p Remote --value 2>/dev/null || true)"
    [[ "${remote}" == "yes" ]] && continue
    seat="$(loginctl show-session "${session}" -p Seat --value 2>/dev/null || true)"
    [[ -n "${seat}" && "${seat}" != "-" ]] || continue
    typ="$(loginctl show-session "${session}" -p Type --value 2>/dev/null || true)"
    case "${typ}" in
      wayland|x11)
        echo "STEP: loginctl terminate-session ${session} (${typ}, ${seat})"
        loginctl terminate-session "${session}" 2>/dev/null || true
        ;;
    esac
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)
}

stop_display_stack() {
  echo "STEP: stop Hyprland session (${CONSOLE_USER})"

  if pgrep -x Hyprland >/dev/null; then
    if hyprctl_as_user dispatch exit; then
      echo "STEP: hyprctl dispatch exit"
    else
      echo "STEP: hyprctl skipped (no socket); continuing with loginctl + ${DISPLAY_MANAGER}" >&2
    fi
    sleep 1
  fi

  terminate_graphical_sessions
  sleep 1

  if id "${CONSOLE_USER}" &>/dev/null; then
    echo "STEP: stop ${CONSOLE_USER} PipeWire (frees GPU HDMI audio)"
    runuser -u "${CONSOLE_USER}" -- systemctl --user stop \
      pipewire pipewire-pulse wireplumber 2>/dev/null || true
    sleep 0.5
  fi

  echo "STEP: stop ${DISPLAY_MANAGER}"
  systemctl stop "${DISPLAY_MANAGER}" 2>/dev/null || true

  local max_iters=$((DISPLAY_STOP_TIMEOUT * 4))
  wait_for_process_exit Hyprland "${max_iters}"
  wait_for_process_exit Xwayland $((max_iters / 2))
  sleep 1
}

start_display_stack() {
  echo "STEP: start ${DISPLAY_MANAGER}"
  systemctl start "${DISPLAY_MANAGER}" 2>/dev/null || true
}

pci_sysfs_dir() {
  echo "/sys/bus/pci/devices/${1}"
}

pci_bound_driver() {
  local pci="$1" link
  link="$(pci_sysfs_dir "${pci}")/driver"
  [[ -L "${link}" ]] || return 0
  basename "$(readlink -f "${link}")"
}

iommu_is_active() {
  local groups=0
  if [[ -d /sys/kernel/iommu_groups ]]; then
    groups="$(find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)"
    [[ "${groups}" -gt 0 ]] && return 0
  fi
  return 1
}

require_iommu() {
  if iommu_is_active; then
    return 0
  fi
  echo "ERROR: IOMMU is not active (no /sys/kernel/iommu_groups)." >&2
  if grep -q AuthenticAMD /proc/cpuinfo 2>/dev/null; then
    echo "  AMD CPU: add amd_iommu=on to kernel cmdline, then reboot." >&2
  else
    echo "  Intel CPU: add intel_iommu=on to kernel cmdline, then reboot." >&2
  fi
  echo "  Helper: sudo vfio-limine-enable" >&2
  grep -oE '(intel_iommu|amd_iommu|iommu)=[^[:space:]]+' /proc/cmdline 2>/dev/null \
    | sed 's/^/  cmdline: /' >&2 || true
  return 1
}

release_dri_device_users() {
  local dev
  command -v fuser >/dev/null || return 0
  shopt -s nullglob
  for dev in /dev/dri/card* /dev/dri/renderD*; do
    fuser -k "${dev}" 2>/dev/null || true
  done
  shopt -u nullglob
}

log_pci_driver_state() {
  local pci driver
  for pci in "${GPU_PCI}" "${AUDIO_PCI}"; do
    driver="$(pci_bound_driver "${pci}")"
    echo "STEP: ${pci} driver=${driver:-<none>}"
  done
}

# RX 7900 HDMI/DP audio (03:00.1) often stays on snd_hda_intel after amdgpu is removed.
release_host_pci_devices() {
  local pci
  log_pci_driver_state
  for pci in "${AUDIO_PCI}" "${GPU_PCI}"; do
    unbind_pci_device "${pci}" 2>/dev/null || true
  done
  sleep 0.5
  log_pci_driver_state
}

gpu_pci_released() {
  local drv
  drv="$(pci_bound_driver "${GPU_PCI}")"
  [[ -z "${drv}" || "${drv}" == "vfio-pci" ]]
}

unload_amdgpu_modules() {
  [[ "${UNLOAD_AMGPU}" == "1" ]] || return 0
  release_dri_device_users
  release_host_pci_devices
  local attempt
  for attempt in 1 2 3 4 5; do
    echo "STEP: unload amdgpu (attempt ${attempt}/5)"
    if modprobe -r amdgpu 2>/dev/null; then
      break
    fi
    sleep 1
    release_dri_device_users
    release_host_pci_devices
    wait_for_process_exit Hyprland 8
    wait_for_process_exit Xwayland 8
  done
  release_host_pci_devices
  if ! gpu_pci_released; then
    echo "ERROR: ${GPU_PCI} still bound to $(pci_bound_driver "${GPU_PCI}")" >&2
    lsmod | grep -E '^(amdgpu|drm)' >&2 || true
    return 1
  fi
  if lsmod | grep -q '^amdgpu '; then
    echo "WARN: amdgpu module still in lsmod but ${GPU_PCI} is unbound; continuing" >&2
  fi
}

load_amdgpu_modules() {
  echo "STEP: modprobe amdgpu"
  modprobe amdgpu 2>/dev/null || true
  udevadm settle 2>/dev/null || true
}

load_vfio_modules() {
  echo "STEP: modprobe vfio-pci / vfio_iommu_type1"
  modprobe vfio-pci
  modprobe vfio_iommu_type1
  modprobe vfio 2>/dev/null || true
}

unbind_pci_device() {
  local pci="$1" driver unbind_path
  driver="$(pci_bound_driver "${pci}")"
  [[ -n "${driver}" ]] || return 0
  unbind_path="$(pci_sysfs_dir "${pci}")/driver/unbind"
  [[ -w "${unbind_path}" ]] || {
    echo "ERROR: cannot unbind ${pci} from ${driver} (missing ${unbind_path})" >&2
    return 1
  }
  echo "STEP: sysfs unbind ${pci} from ${driver}"
  echo "${pci}" > "${unbind_path}"
}

register_vfio_pci_id() {
  local pci="$1" vendor device
  vendor="$(< "$(pci_sysfs_dir "${pci}")/vendor")"
  device="$(< "$(pci_sysfs_dir "${pci}")/device")"
  vendor="${vendor#0x}"
  device="${device#0x}"
  echo "STEP: vfio-pci new_id ${vendor} ${device} (${pci})"
  echo "${vendor} ${device}" > /sys/bus/pci/drivers/vfio-pci/new_id 2>/dev/null || true
}

bind_pci_to_vfio() {
  local pci="$1"
  if [[ "$(pci_bound_driver "${pci}")" == "vfio-pci" ]]; then
    echo "STEP: ${pci} already on vfio-pci"
    return 0
  fi
  register_vfio_pci_id "${pci}"
  local bind_path="/sys/bus/pci/drivers/vfio-pci/bind"
  [[ -w "${bind_path}" ]] || {
    echo "ERROR: cannot bind ${pci} to vfio-pci" >&2
    return 1
  }
  echo "STEP: sysfs bind ${pci} to vfio-pci"
  echo "${pci}" > "${bind_path}"
  [[ "$(pci_bound_driver "${pci}")" == "vfio-pci" ]]
}

unbind_pci_from_vfio() {
  local pci="$1" unbind_path
  [[ "$(pci_bound_driver "${pci}")" == "vfio-pci" ]] || return 0
  unbind_path="/sys/bus/pci/drivers/vfio-pci/unbind"
  [[ -w "${unbind_path}" ]] || return 1
  echo "STEP: sysfs unbind ${pci} from vfio-pci"
  echo "${pci}" > "${unbind_path}"
}

bind_pci_to_amdgpu() {
  local pci="$1"
  if [[ "$(pci_bound_driver "${pci}")" == "amdgpu" ]]; then
    return 0
  fi
  local bind_path="/sys/bus/pci/drivers/amdgpu/bind"
  [[ -w "${bind_path}" ]] || return 0
  echo "STEP: sysfs bind ${pci} to amdgpu"
  echo "${pci}" > "${bind_path}" 2>/dev/null || true
}

detach_pci_node() {
  local node="$1" pci="$2"
  if [[ "$(pci_bound_driver "${pci}")" == "vfio-pci" ]]; then
    echo "STEP: ${pci} already detached (vfio-pci)"
    return 0
  fi
  unbind_pci_device "${pci}" || true
  echo "STEP: nodedev-detach ${node}"
  if virsh nodedev-detach "${node}" 2>/dev/null; then
    return 0
  fi
  echo "STEP: virsh nodedev-detach ${node} failed; binding ${pci} via sysfs" >&2
  bind_pci_to_vfio "${pci}"
}

detach_gpu_from_host() {
  require_iommu || return 1
  load_vfio_modules
  release_host_pci_devices
  # Audio first (often snd_hda_intel); then GPU.
  detach_pci_node "${AUDIO_NODE}" "${AUDIO_PCI}"
  detach_pci_node "${GPU_NODE}" "${GPU_PCI}"
  log_pci_driver_state
  gpu_pci_released || {
    echo "ERROR: GPU not on vfio-pci after detach" >&2
    return 1
  }
  [[ "$(pci_bound_driver "${AUDIO_PCI}")" == "vfio-pci" ]] || {
    echo "ERROR: audio ${AUDIO_PCI} not on vfio-pci after detach" >&2
    return 1
  }
}

reattach_pci_node() {
  local node="$1" pci="$2"
  unbind_pci_from_vfio "${pci}" || true
  echo "STEP: nodedev-reattach ${node}"
  virsh nodedev-reattach "${node}" 2>/dev/null || true
  bind_pci_to_amdgpu "${pci}"
}

reattach_gpu_to_host() {
  reattach_pci_node "${AUDIO_NODE}" "${AUDIO_PCI}"
  reattach_pci_node "${GPU_NODE}" "${GPU_PCI}"
}

gpu_handoff_prepare_begin() {
  passthrough_enabled || {
    echo "Passthrough disabled (${ENABLE_FILE} missing). Hook skipped."
    return 0
  }

  stop_display_stack
  echo "STEP: bind_vtconsoles 0"
  bind_vtconsoles 0
  echo "STEP: bind_efi_framebuffer unbind"
  bind_efi_framebuffer unbind
  echo "STEP: sleep ${DETACH_SLEEP}"
  sleep "${DETACH_SLEEP}"

  unload_amdgpu_modules
  detach_gpu_from_host
  echo "STEP: prepare/begin complete — libvirt may start QEMU now"
}

gpu_handoff_release_end() {
  if [[ "${GPU_HANDOFF_FORCE:-0}" != "1" ]] && ! passthrough_enabled; then
    echo "Passthrough disabled (${ENABLE_FILE} missing). Hook skipped."
    return 0
  fi

  reattach_gpu_to_host
  load_amdgpu_modules
  echo "STEP: bind_vtconsoles 1"
  bind_vtconsoles 1
  echo "STEP: bind_efi_framebuffer bind"
  bind_efi_framebuffer bind
  start_display_stack
  echo "STEP: release/end complete"
}

gpu_handoff_rollback() {
  local exit_code=$?
  set +e
  echo "ROLLBACK: prepare failed (exit=${exit_code})"
  reattach_gpu_to_host
  load_amdgpu_modules
  bind_vtconsoles 1
  bind_efi_framebuffer bind
  start_display_stack
  echo "ROLLBACK: done"
  exit "${exit_code}"
}
