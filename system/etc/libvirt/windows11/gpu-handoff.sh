# Shared single-GPU handoff for windows11 (sourced by libvirt hooks).
# Pattern: VFIO-Tools qemu.d + joeknock90 Single-GPU-Passthrough + Hyprland stop.
set -o pipefail

# shellcheck source=/dev/null
source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/paths.sh"
# shellcheck source=/dev/null
[[ -f "${HOOK_LOG_LIB}" ]] && source "${HOOK_LOG_LIB}"

CONF="${GPU_HANDOFF_CONF}"
if [[ -f "${CONF}" ]]; then
  # shellcheck source=/dev/null
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
CONSOLE_USER="${CONSOLE_USER:-jacke}"
DETACH_SLEEP="${DETACH_SLEEP:-3}"
SKIP_EFI_FB="${SKIP_EFI_FB:-0}"
UNLOAD_AMGPU="${UNLOAD_AMGPU:-1}"
# Max seconds to wait for compositor processes after stopping the display manager.
DISPLAY_STOP_TIMEOUT="${DISPLAY_STOP_TIMEOUT:-12}"
AUTO_RESTORE_HYPRLAND="${AUTO_RESTORE_HYPRLAND:-0}"
HOOK_DRM_WAIT_SECONDS="${HOOK_DRM_WAIT_SECONDS:-20}"
PCI_REMOVE_RESCAN="${PCI_REMOVE_RESCAN:-1}"
REATTACH_SETTLE="${REATTACH_SETTLE:-5}"
# Extra wait after rescan before amdgpu probe (PSP/SMU). udev stays frozen.
AMDGPU_PROBE_SETTLE="${AMDGPU_PROBE_SETTLE:-10}"
AMDGPU_LOAD_RETRIES="${AMDGPU_LOAD_RETRIES:-2}"
UDEV_EXEC_QUEUE_FROZEN="${UDEV_EXEC_QUEUE_FROZEN:-0}"

if ! declare -p DISPLAY_MANAGER_UNITS >/dev/null 2>&1; then
  DISPLAY_MANAGER_UNITS=("${DISPLAY_MANAGER:-display-manager.service}")
fi

if ! declare -p USB_HID_IDS >/dev/null 2>&1; then
  USB_HID_IDS=(1532:007a 3434:0108 1532:007b 361d:0100 041e:324d)
fi

passthrough_enabled() {
  [[ -e "${ENABLE_FILE}" ]]
}

# Read libvirt domain XML from hook stdin without hanging on a TTY.
# Libvirt pipes XML on stdin. Manual runs (force-stop / revert-host) are on a
# TTY — bare `cat` waits forever for keyboard input (force-stop looked hung).
read_hook_domain_xml() {
  if [[ -n "${DOMAIN_XML:-}" ]]; then
    export DOMAIN_XML
    return 0
  fi
  if [[ -n "${DOMAIN_XML_FILE:-}" && -f "${DOMAIN_XML_FILE}" ]]; then
    DOMAIN_XML="$(< "${DOMAIN_XML_FILE}")"
    export DOMAIN_XML
    return 0
  fi
  if [[ -t 0 ]]; then
    DOMAIN_XML="$(timeout 5 virsh dumpxml "${DOMAIN}" 2>/dev/null || true)"
  else
    DOMAIN_XML="$(cat || true)"
  fi
  export DOMAIN_XML
}

# True when this domain XML assigns the host AMD GPU (source BDF, not guest addr).
# Prefer DOMAIN_XML from libvirt hook stdin — NEVER virsh dumpxml during prepare/start
# (that deadlocks: start holds domain lock → dumpxml waits → hook never finishes).
domain_has_gpu_hostdev() {
  local xml="${DOMAIN_XML:-}"
  if [[ -z "${xml}" ]]; then
    if [[ -n "${DOMAIN_XML_FILE:-}" && -f "${DOMAIN_XML_FILE}" ]]; then
      xml="$(< "${DOMAIN_XML_FILE}")"
    else
      # Safe only outside an in-flight domain start/stop hook.
      xml="$(timeout 5 virsh dumpxml "${DOMAIN}" 2>/dev/null)" || return 1
    fi
  fi
  # Match host BDF inside <hostdev><source> only (not guest <address>).
  DOMAIN_XML_PROBE="${xml}" python3 <<'PY'
import os, re, sys
text = os.environ.get("DOMAIN_XML_PROBE", "")
for hostdev in re.findall(r"<hostdev\b[^>]*>.*?</hostdev>", text, flags=re.S | re.I):
    if not re.search(r'type\s*=\s*["\']pci["\']', hostdev, re.I):
        continue
    src = re.search(r"<source>(.*?)</source>", hostdev, flags=re.S | re.I)
    if not src:
        continue
    body = src.group(1)
    if (
        re.search(r'bus\s*=\s*["\']0x03["\']', body, re.I)
        and re.search(r'slot\s*=\s*["\']0x00["\']', body, re.I)
        and re.search(r'function\s*=\s*["\']0x0["\']', body, re.I)
    ):
        sys.exit(0)
sys.exit(1)
PY
}

gpu_on_vfio() {
  [[ "$(pci_bound_driver "${GPU_PCI}")" == "vfio-pci" ]]
}

safe_chvt() {
  if timeout 2 chvt "$1" >/dev/null 2>&1; then
    return 0
  fi
  echo "WARN: chvt $1 timed out" >&2
  return 1
}

wait_for_drm() {
  local max="${1:-${DRM_WAIT_SECONDS:-120}}" i
  for ((i = 1; i <= max; i++)); do
    if compgen -G '/dev/dri/card*' >/dev/null; then
      echo "STEP: DRM ready ($(echo /dev/dri/card*)) after ${i}s"
      return 0
    fi
    if (( i % 10 == 0 )); then
      echo "STEP: waiting for /dev/dri (${i}/${max}s) gpu=$(pci_bound_driver "${GPU_PCI}")"
    fi
    sleep 1
  done
  echo "WARN: no /dev/dri/card* after ${max}s (gpu=$(pci_bound_driver "${GPU_PCI}"))" >&2
  return 1
}

drm_ready() {
  compgen -G '/dev/dri/card*' >/dev/null
}

bind_vtconsoles() {
  local value="$1" vt name vt_dir
  shopt -s nullglob
  for vt in /sys/class/vtconsole/vtcon*/bind; do
    vt_dir="${vt%/bind}"
    name="$(cat "${vt_dir}/name" 2>/dev/null || true)"
    # DRM framebuffer vtcon bind/unbind after VFIO often wedges in D-state;
    # amdgpu (un)load owns that console. Dummy vtcon is enough.
    if [[ "${name}" == *"frame buffer"* ]]; then
      echo "STEP: skip vtcon ${value} for ${name}"
      continue
    fi
    if command -v timeout >/dev/null; then
      timeout 2 sh -c "echo '${value}' > '${vt}'" 2>/dev/null || \
        echo "WARN: vtcon bind ${value} timed out on ${vt}" >&2
    else
      echo "${value}" > "${vt}" 2>/dev/null || true
    fi
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
    # Hyprland ≥0.56: Lua dispatcher. Fall back to legacy + loginctl.
    if hyprctl_as_user dispatch 'hl.dsp.exit()' 2>/dev/null; then
      echo "STEP: hyprctl dispatch hl.dsp.exit()"
    elif hyprctl_as_user dispatch exit 2>/dev/null; then
      echo "STEP: hyprctl dispatch exit"
    else
      echo "STEP: hyprctl skipped (no socket); continuing with loginctl + display manager" >&2
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

  local unit
  for unit in "${DISPLAY_MANAGER_UNITS[@]}"; do
    [[ -n "${unit}" ]] || continue
    echo "STEP: stop ${unit}"
    systemctl stop "${unit}" 2>/dev/null || true
  done

  local max_iters=$((DISPLAY_STOP_TIMEOUT * 4))
  wait_for_process_exit Hyprland "${max_iters}"
  wait_for_process_exit Xwayland $((max_iters / 2))
  sleep 1
}

settle_console_input() {
  echo "STEP: settle console/input"
  udevadm trigger --subsystem-match=input 2>/dev/null || true
  udevadm trigger --subsystem-match=usb 2>/dev/null || true
  timeout 3 udevadm settle 2>/dev/null || true
  # Never block post-hook on vconsole-setup — it can hang after GPU handoff and
  # prevents Hyprland restore from running.
  timeout 3 systemctl try-restart systemd-vconsole-setup.service 2>/dev/null || true
}

start_ly_units() {
  local unit
  for unit in "${DISPLAY_MANAGER_UNITS[@]}"; do
    [[ -n "${unit}" ]] || continue
    echo "STEP: restart ${unit} (login manager)"
    timeout 15 systemctl restart "${unit}" 2>/dev/null || \
      echo "WARN: ${unit} failed to start" >&2
  done
  safe_chvt 1
}

# Survives libvirt killing the qemu hook. Full GPU restore + ly live here —
# never modprobe amdgpu inside release/end (Navi 31 BUG wedges the hook).
queue_host_gpu_restore() {
  local unit="windows11-restore-display.service"
  local bin="${DOTFILES_SYSTEM}/usr/local/bin/windows11-restore-display"
  [[ -x "${bin}" ]] || bin="/usr/local/bin/windows11-restore-display"
  if [[ ! -x "${bin}" ]]; then
    echo "ERROR: windows11-restore-display missing (${bin})" >&2
    return 1
  fi
  systemctl reset-failed "${unit}" 2>/dev/null || true
  systemctl stop "${unit}" 2>/dev/null || true
  echo "STEP: queue ${unit} → ${bin}"
  # Oneshot outlives qemu hook. --no-block so release/end returns immediately.
  systemd-run --unit="${unit}" --collect --no-block \
    --description="After VFIO: PCI rescan + amdgpu + ly" \
    "${bin}" >/dev/null \
    || echo "WARN: systemd-run ${unit} failed" >&2
}

# Back-compat name used by older comments / manual calls.
queue_ly_after_drm() {
  queue_host_gpu_restore
}

start_hyprland_as_user() {
  local uid="$1" runtime="$2" home="$3" log="$4" unit="windows11-restore-hyprland.service"
  local dbus_addr="unix:path=${runtime}/bus"

  if [[ ! -x /usr/bin/start-hyprland ]]; then
    echo "WARN: /usr/bin/start-hyprland missing" >&2
    return 1
  fi

  # systemd --user unit outlives the libvirt hook. uwsm from the hook never
  # gets a seat/VT, so start-hyprland is the compositor launcher.
  if command -v systemd-run >/dev/null; then
    echo "STEP: systemd-run --user start-hyprland"
    systemctl --user --machine="${CONSOLE_USER}@" reset-failed "${unit}" 2>/dev/null || true
    systemctl --user --machine="${CONSOLE_USER}@" stop "${unit}" 2>/dev/null || true
    if systemd-run --quiet --machine="${CONSOLE_USER}@" --user \
      --unit="${unit}" --collect \
      --setenv=XDG_RUNTIME_DIR="${runtime}" \
      --setenv=HOME="${home}" \
      --setenv=XDG_VTNR=1 \
      --setenv=XDG_SEAT=seat0 \
      --setenv=XDG_SESSION_TYPE=wayland \
      --setenv=XDG_CURRENT_DESKTOP=Hyprland \
      --setenv=DBUS_SESSION_BUS_ADDRESS="${dbus_addr}" \
      /usr/bin/start-hyprland; then
      return 0
    fi
    echo "WARN: systemd-run start-hyprland failed; trying runuser" >&2
  fi

  echo "STEP: runuser start-hyprland"
  nohup runuser -u "${CONSOLE_USER}" -- env \
    XDG_RUNTIME_DIR="${runtime}" \
    HOME="${home}" \
    XDG_VTNR=1 \
    XDG_SEAT=seat0 \
    XDG_SESSION_TYPE=wayland \
    XDG_CURRENT_DESKTOP=Hyprland \
    DBUS_SESSION_BUS_ADDRESS="${dbus_addr}" \
    /usr/bin/start-hyprland \
    </dev/null >>"${log}" 2>&1 &
}

restore_hyprland_session() {
  [[ "${AUTO_RESTORE_HYPRLAND:-0}" == "1" ]] || return 1
  if pgrep -x Hyprland >/dev/null; then
    echo "STEP: Hyprland already running"
    safe_chvt 1
    return 0
  fi

  wait_for_drm || return 1

  local unit uid runtime log home
  log="${WINDOWS11_HOOK_LOG:-/var/log/windows11-passthrough-hook.log}"
  echo "STEP: restore Hyprland session (${CONSOLE_USER})"
  for unit in "${DISPLAY_MANAGER_UNITS[@]}"; do
    [[ -n "${unit}" ]] || continue
    timeout 8 systemctl stop "${unit}" 2>/dev/null || true
  done
  safe_chvt 1

  uid="$(id -u "${CONSOLE_USER}" 2>/dev/null)" || return 1
  runtime="/run/user/${uid}"
  if [[ ! -d "${runtime}" ]]; then
    loginctl enable-linger "${CONSOLE_USER}" 2>/dev/null || true
    timeout 8 systemctl start "user@${uid}.service" 2>/dev/null || true
    sleep 1
  fi
  [[ -d "${runtime}" ]] || {
    echo "WARN: missing ${runtime}; cannot start Hyprland" >&2
    return 1
  }

  home="$(getent passwd "${CONSOLE_USER}" | cut -d: -f6)"
  start_hyprland_as_user "${uid}" "${runtime}" "${home}" "${log}" || return 1

  local i
  for ((i = 1; i <= 60; i++)); do
    if pgrep -x Hyprland >/dev/null; then
      echo "STEP: Hyprland running after restore"
      safe_chvt 1
      return 0
    fi
    sleep 0.5
  done
  echo "WARN: Hyprland did not start within 30s (see ${log})" >&2
  return 1
}

start_display_stack() {
  # Always bring ly back. Skipping it after a failed Hyprland restore is what
  # left a black screen (no login, no compositor) and forced a power-button reboot.
  echo "STEP: start login manager after VM"
  start_ly_units
  settle_console_input
  if [[ "${AUTO_RESTORE_HYPRLAND:-0}" == "1" ]]; then
    restore_hyprland_session || true
  fi
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

pci_reset_device() {
  local pci="$1" reset_path
  reset_path="$(pci_sysfs_dir "${pci}")/reset"
  [[ -f "${reset_path}" ]] || return 0
  echo "STEP: PCI FLR reset ${pci}"
  if ! echo 1 >"${reset_path}" 2>/dev/null; then
    echo "WARN: PCI reset failed for ${pci}" >&2
    return 1
  fi
  return 0
}

pci_remove_device() {
  local pci="$1" remove_path
  remove_path="$(pci_sysfs_dir "${pci}")/remove"
  [[ -f "${remove_path}" ]] || return 0
  echo "STEP: PCI remove ${pci}"
  echo 1 >"${remove_path}" 2>/dev/null || \
    echo "WARN: PCI remove failed for ${pci}" >&2
}

pci_bus_rescan() {
  echo "STEP: PCI bus rescan"
  echo 1 >/sys/bus/pci/rescan 2>/dev/null || \
    echo "WARN: PCI rescan failed" >&2
  sleep 1
  # Do not udevadm settle here while frozen — settle can wait on a hung probe.
}

udev_freeze() {
  [[ "${UDEV_EXEC_QUEUE_FROZEN}" == "1" ]] && return 0
  echo "STEP: udevadm stop-exec-queue (block auto amdgpu/snd bind)"
  udevadm control --stop-exec-queue 2>/dev/null || true
  UDEV_EXEC_QUEUE_FROZEN=1
}

udev_thaw() {
  [[ "${UDEV_EXEC_QUEUE_FROZEN}" == "1" ]] || return 0
  echo "STEP: udevadm start-exec-queue"
  udevadm control --start-exec-queue 2>/dev/null || true
  UDEV_EXEC_QUEUE_FROZEN=0
  timeout 5 udevadm settle 2>/dev/null || true
}

pci_set_driver_override() {
  local pci="$1" val="${2-}" path
  path="$(pci_sysfs_dir "${pci}")/driver_override"
  [[ -e "${path}" ]] || return 0
  echo "STEP: ${pci} driver_override=${val:-<empty>}"
  printf '%s\n' "${val}" >"${path}" 2>/dev/null || true
}

pci_wait_sysfs() {
  local pci="$1" max="${2:-15}" i
  for ((i = 1; i <= max; i++)); do
    [[ -e "$(pci_sysfs_dir "${pci}")" ]] && return 0
    sleep 1
  done
  echo "WARN: ${pci} sysfs missing after ${max}s" >&2
  return 1
}

# Power-cycle GPU+audio via sysfs remove/rescan before amdgpu probe.
# Leave udev frozen and driver_override=none so udev cannot probe amdgpu.
# Clearing override + start-exec-queue was racing a naked Navi 31 probe
# (kernel BUG amdgpu_device_mm_access).
pci_remove_rescan_gpu() {
  [[ "${PCI_REMOVE_RESCAN}" == "1" ]] || return 0
  echo "STEP: PCI remove/rescan GPU path (settle=${REATTACH_SETTLE}s probe=${AMDGPU_PROBE_SETTLE}s)"
  udev_freeze
  unbind_pci_device "${AUDIO_PCI}" 2>/dev/null || true
  unbind_pci_device "${GPU_PCI}" 2>/dev/null || true
  # Drop half-loaded amdgpu from a prior BUG so it cannot re-bind mid-rescan.
  modprobe -r amdgpu 2>/dev/null || true
  pci_reset_device "${AUDIO_PCI}" 2>/dev/null || true
  pci_reset_device "${GPU_PCI}" 2>/dev/null || true
  pci_remove_device "${AUDIO_PCI}"
  pci_remove_device "${GPU_PCI}"
  sleep "${REATTACH_SETTLE}"
  pci_bus_rescan
  pci_wait_sysfs "${GPU_PCI}" 15 || true
  pci_wait_sysfs "${AUDIO_PCI}" 5 || true
  pci_set_driver_override "${GPU_PCI}" none
  pci_set_driver_override "${AUDIO_PCI}" none
  echo "STEP: wait ${AMDGPU_PROBE_SETTLE}s after rescan before amdgpu probe"
  sleep "${AMDGPU_PROBE_SETTLE}"
  log_pci_driver_state
}

bind_pci_to_snd_hda() {
  local pci="${AUDIO_PCI}" bind_path drv
  drv="$(pci_bound_driver "${pci}")"
  [[ "${drv}" == "snd_hda_intel" ]] && return 0
  if [[ -n "${drv}" ]]; then
    unbind_pci_device "${pci}" 2>/dev/null || true
  fi
  bind_path="/sys/bus/pci/drivers/snd_hda_intel/bind"
  [[ -w "${bind_path}" ]] || {
    echo "WARN: snd_hda_intel bind path missing" >&2
    return 1
  }
  echo "STEP: sysfs bind ${pci} to snd_hda_intel"
  echo "${pci}" >"${bind_path}" 2>/dev/null || true
}

load_amdgpu_finish() {
  local rc="$1"
  if [[ "${rc}" -eq 0 ]]; then
    bind_pci_to_snd_hda || true
    pci_set_driver_override "${GPU_PCI}" ""
    pci_set_driver_override "${AUDIO_PCI}" ""
  else
    # Keep none so thaw does not immediately udev-probe a dead GPU.
    pci_set_driver_override "${GPU_PCI}" none
    pci_set_driver_override "${AUDIO_PCI}" none
  fi
  udev_thaw
  return "${rc}"
}

load_amdgpu_modules() {
  local attempt max_attempts rc wait_s
  max_attempts="${AMDGPU_LOAD_RETRIES:-2}"
  echo "STEP: load amdgpu (Navi 31 after VFIO — remove/rescan first; probe can take ~90s)"
  udev_freeze

  for ((attempt = 1; attempt <= max_attempts; attempt++)); do
    if drm_ready && [[ "$(pci_bound_driver "${GPU_PCI}")" == "amdgpu" ]]; then
      echo "STEP: DRM already up on attempt ${attempt}"
      load_amdgpu_finish 0
      return 0
    fi

    # Half-bound amdgpu with no DRM is the BUG leftover. Do not FLR/rescan —
    # sysfs reset after amdgpu_device_mm_access hangs in D-state.
    if [[ "$(pci_bound_driver "${GPU_PCI}")" == "amdgpu" ]] && ! drm_ready; then
      echo "ERROR: ${GPU_PCI} on amdgpu without DRM after failed probe — abort (no FLR). Cold power-off required." >&2
      load_amdgpu_finish 1
      return 1
    fi

    if [[ "${attempt}" -gt 1 ]]; then
      pci_remove_rescan_gpu || true
    elif [[ ! -e "$(pci_sysfs_dir "${GPU_PCI}")" ]]; then
      echo "STEP: ${GPU_PCI} missing after reattach — rescan"
      pci_remove_rescan_gpu || true
    fi

    pci_set_driver_override "${GPU_PCI}" amdgpu
    pci_set_driver_override "${AUDIO_PCI}" none

    if ! lsmod | grep -q '^amdgpu '; then
      echo "STEP: modprobe amdgpu (attempt ${attempt}/${max_attempts})"
      rc=0
      modprobe amdgpu || rc=$?
      if [[ "${rc}" -ne 0 ]]; then
        echo "WARN: modprobe amdgpu returned ${rc} (139=SIGSEGV/kernel BUG)" >&2
        if [[ "${rc}" -eq 139 ]]; then
          # Navi 31: amdgpu_device_mm_access BUG. FLR/remove/rescan after
          # this D-states restore-display and wedges udev until cold reboot.
          echo "ERROR: amdgpu probe BUG — abort restore (no FLR/rescan). Cold power-off required." >&2
          load_amdgpu_finish 1
          return 1
        fi
        if [[ -e "$(pci_sysfs_dir "${GPU_PCI}")" ]]; then
          unbind_pci_device "${GPU_PCI}" 2>/dev/null || true
        fi
        modprobe -r amdgpu 2>/dev/null || true
        pci_set_driver_override "${GPU_PCI}" none
        continue
      fi
    else
      echo "STEP: amdgpu module already loaded; binding ${GPU_PCI}"
      bind_pci_to_amdgpu "${GPU_PCI}" || true
    fi

    bind_pci_to_amdgpu "${GPU_PCI}" || true

    wait_s="${HOOK_DRM_WAIT_SECONDS:-20}"
    if [[ "${WINDOWS11_FULL_DRM_WAIT:-0}" == "1" ]]; then
      wait_s="${DRM_WAIT_SECONDS:-120}"
    fi
    if wait_for_drm "${wait_s}"; then
      load_amdgpu_finish 0
      return 0
    fi
    echo "WARN: DRM not ready after attempt ${attempt}/${max_attempts}" >&2
    pci_set_driver_override "${GPU_PCI}" none
  done

  echo "ERROR: amdgpu failed to produce /dev/dri after ${max_attempts} attempts" >&2
  echo "ERROR: RX 7900 XTX after Windows VFIO often needs a cold reboot (power off)" >&2
  load_amdgpu_finish 1
  return 1
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
  if command -v timeout >/dev/null; then
    timeout 3 sh -c "echo '${pci}' > '${unbind_path}'" || {
      echo "WARN: unbind ${pci} from ${driver} timed out" >&2
      return 1
    }
  else
    echo "${pci}" > "${unbind_path}"
  fi
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
  if command -v timeout >/dev/null; then
    timeout 3 sh -c "echo '${pci}' > '${unbind_path}'" || {
      echo "WARN: vfio unbind timed out for ${pci}; continue recovery path" >&2
      return 1
    }
  else
    echo "${pci}" > "${unbind_path}"
  fi
}

unregister_vfio_pci_id() {
  local pci="$1" vendor device remove_id
  remove_id="/sys/bus/pci/drivers/vfio-pci/remove_id"
  [[ -e "$(pci_sysfs_dir "${pci}")/vendor" ]] || return 0
  [[ -w "${remove_id}" ]] || return 0
  vendor="$(< "$(pci_sysfs_dir "${pci}")/vendor")"
  device="$(< "$(pci_sysfs_dir "${pci}")/device")"
  vendor="${vendor#0x}"
  device="${device#0x}"
  echo "STEP: vfio-pci remove_id ${vendor} ${device} (${pci})"
  echo "${vendor} ${device}" > "${remove_id}" 2>/dev/null || true
}

bind_pci_to_amdgpu() {
  local pci="$1"
  # HDMI audio is snd_hda_intel, never amdgpu.
  [[ "${pci}" == "${AUDIO_PCI}" ]] && return 0
  if [[ "$(pci_bound_driver "${pci}")" == "amdgpu" ]]; then
    return 0
  fi
  local bind_path="/sys/bus/pci/drivers/amdgpu/bind"
  [[ -w "${bind_path}" ]] || {
    echo "WARN: amdgpu bind path missing for ${pci}" >&2
    return 1
  }
  echo "STEP: sysfs bind ${pci} to amdgpu"
  echo "${pci}" > "${bind_path}" 2>/dev/null || true
  [[ "$(pci_bound_driver "${pci}")" == "amdgpu" ]]
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
  unregister_vfio_pci_id "${pci}"
  # With managed=no we own rebinding. Skip virsh nodedev-reattach — it can
  # trigger a naked amdgpu probe before PCI remove/rescan.
  echo "STEP: vfio released ${pci} (node=${node}; host bind deferred)"
}

reattach_gpu_to_host() {
  # Hook path: only peel vfio. PCI remove/rescan + amdgpu happen in
  # windows11-restore-display (async) — never block/bug qemu release.
  reattach_pci_node "${AUDIO_NODE}" "${AUDIO_PCI}"
  reattach_pci_node "${GPU_NODE}" "${GPU_PCI}"
  log_pci_driver_state
}

gpu_handoff_prepare_begin() {
  passthrough_enabled || {
    echo "Passthrough disabled (${ENABLE_FILE} missing). Hook skipped."
    return 0
  }

  if ! domain_has_gpu_hostdev; then
    echo "Domain ${DOMAIN} has no GPU PCI hostdev — skip display kill / VFIO handoff (VNC/console)."
    return 0
  fi

  require_iommu || return 1
  load_vfio_modules

  stop_display_stack
  safe_chvt 63 || safe_chvt 2 || true
  release_dri_device_users
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

  if [[ "${GPU_HANDOFF_FORCE:-0}" == "1" ]]; then
    if ! gpu_on_vfio && pgrep -x Hyprland >/dev/null && drm_ready; then
      echo "FORCE: GPU already on host driver and Hyprland up — nothing to do."
      return 0
    fi
    echo "FORCE: restoring host GPU/display (vfio=$(gpu_on_vfio && echo yes || echo no))"
  elif ! domain_has_gpu_hostdev; then
    echo "Domain ${DOMAIN} has no GPU PCI hostdev — skip GPU reattach / display restore."
    return 0
  fi

  # 1) Peel vfio off GPU (fast, safe).
  reattach_gpu_to_host
  # 2) Queue durable oneshot: remove/rescan + modprobe amdgpu + ly.
  #    Do NOT modprobe here — kernel BUG at amdgpu_device_mm_access kills display
  #    and can stall this hook until libvirt times out → black screen.
  queue_host_gpu_restore
  # 3) Bring ly up immediately (text console). Async job restarts it after DRM.
  settle_console_input
  start_ly_units
  safe_chvt 1 || true
  echo "STEP: release/end complete (GPU restore running async)"
}

gpu_handoff_rollback() {
  local exit_code=$?
  set +e
  echo "ROLLBACK: prepare failed (exit=${exit_code})"
  reattach_gpu_to_host
  queue_host_gpu_restore
  settle_console_input
  start_ly_units
  echo "ROLLBACK: done (GPU restore queued)"
  exit "${exit_code}"
}
