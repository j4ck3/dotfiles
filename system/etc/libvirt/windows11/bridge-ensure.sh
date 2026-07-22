# Shared LAN bridge helpers for windows11 passthrough VMs.
# Sourced by libvirt started hooks and windows11-network.
set -o pipefail

LAN_BRIDGE="${LAN_BRIDGE:-br0}"

bridge_iface_on_bridge() {
  local bridge="$1"
  bridge link show 2>/dev/null | awk -v br="${bridge}" '$0 ~ "master " br { sub(":", "", $2); print $2; exit }'
}

domain_tap_iface() {
  local domain="$1"
  virsh -c "${VIRSH_DEFAULT_CONNECT_URI:-qemu:///system}" domiflist "${domain}" 2>/dev/null \
    | awk 'NR == 2 { print $1 }'
}

tap_master_bridge() {
  local tap="$1"
  ip -o link show "${tap}" 2>/dev/null | awk '{for (i = 1; i <= NF; i++) if ($i == "master") print $(i + 1)}'
}

ensure_nm_bridge_up() {
  command -v nmcli >/dev/null || return 0
  nmcli connection up "${LAN_BRIDGE}" 2>/dev/null || true
  local slave
  slave="$(bridge_iface_on_bridge "${LAN_BRIDGE}" || true)"
  if [[ -n "${slave}" ]] && nmcli connection show "${LAN_BRIDGE}-${slave}" &>/dev/null; then
    nmcli connection up "${LAN_BRIDGE}-${slave}" 2>/dev/null || true
  fi
}

attach_tap_to_bridge() {
  local tap="$1" bridge="$2"
  [[ -n "${tap}" && -n "${bridge}" ]] || return 1
  [[ -d "/sys/class/net/${bridge}/bridge" ]] || {
    echo "ERROR: bridge ${bridge} does not exist" >&2
    return 1
  }
  ip link set "${tap}" up 2>/dev/null || true
  if [[ "$(tap_master_bridge "${tap}")" == "${bridge}" ]]; then
    return 0
  fi
  echo "STEP: attach ${tap} to ${bridge}"
  ip link set "${tap}" master "${bridge}"
}

bridge_ensure_for_domain() {
  local domain="$1" tap master
  export LC_ALL=C LANG=C
  ensure_nm_bridge_up
  tap="$(domain_tap_iface "${domain}")"
  if [[ -z "${tap}" ]]; then
    echo "WARN: no tap interface for ${domain}" >&2
    return 1
  fi
  master="$(tap_master_bridge "${tap}")"
  if [[ "${master}" == "${LAN_BRIDGE}" ]]; then
    echo "OK: ${tap} already on ${LAN_BRIDGE}"
    return 0
  fi
  attach_tap_to_bridge "${tap}" "${LAN_BRIDGE}"
}

bridge_status_for_domain() {
  local domain="$1" tap master
  tap="$(domain_tap_iface "${domain}")"
  master="$(tap_master_bridge "${tap}")"
  echo "  tap: ${tap:-<none>}"
  echo "  master: ${master:-<none>} (want ${LAN_BRIDGE})"
  if [[ -n "${tap}" && "${master}" == "${LAN_BRIDGE}" ]]; then
    return 0
  fi
  return 1
}

# libvirt 12+ often omits managed="no" from dumpxml even when the NIC is bridge+br0.
domain_xml_has_lan_bridge() {
  local domain="${1:-${DOMAIN:-windows11-stealth}}"
  local bridge="${2:-${LAN_BRIDGE:-br0}}"
  local uri="${VIRSH_DEFAULT_CONNECT_URI:-${CONNECT_URI:-qemu:///system}}"
  python3 - "${domain}" "${bridge}" "${uri}" <<'PY'
import subprocess
import sys
import xml.etree.ElementTree as ET

domain, bridge, uri = sys.argv[1:4]
try:
    xml = subprocess.check_output(
        ["virsh", "-c", uri, "dumpxml", domain],
        text=True,
        stderr=subprocess.DEVNULL,
    )
except subprocess.CalledProcessError:
    sys.exit(1)
root = ET.fromstring(xml)
devices = root.find("devices")
if devices is None:
    sys.exit(1)
for iface in devices.findall("interface"):
    if iface.get("type") != "bridge":
        continue
    src = iface.find("source")
    if src is not None and src.get("bridge") == bridge:
        sys.exit(0)
sys.exit(1)
PY
}
