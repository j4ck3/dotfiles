#!/usr/bin/env bash
# Install LACT GPU fan curve and enable the daemon.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
config_src="${repo}/etc/lact/config.yaml"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

if ! command -v lact >/dev/null 2>&1; then
  echo "lact is not installed. Install it first, e.g.:" >&2
  echo "  pacman -S --needed lact" >&2
  exit 1
fi

overdrive_src="${repo}/etc/modprobe.d/99-amdgpu-overdrive.conf"
if [[ -f "${overdrive_src}" ]]; then
  install -m 0644 "${overdrive_src}" /etc/modprobe.d/99-amdgpu-overdrive.conf
fi

install -d -m 0755 /etc/lact
install -m 0644 "${config_src}" /etc/lact/config.yaml

systemctl enable --now lactd
systemctl restart lactd

if [[ ! -f /etc/modprobe.d/99-amdgpu-overdrive.conf ]]; then
  echo "Warning: amdgpu overdrive not enabled. Install ${repo}/etc/modprobe.d/99-amdgpu-overdrive.conf and reboot." >&2
fi

echo "LACT installed (RX 7900 XTX undervolt + fan curve)."
echo "  Status:   systemctl status lactd"
echo "  Verify:   cat /sys/class/drm/card*/device/pp_od_clk_voltage"
echo "  GUI:      lact"
echo "  Tweaks:   edit ${config_src} then re-run this script"
