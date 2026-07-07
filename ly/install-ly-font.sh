#!/usr/bin/env bash
# Install Ly console font drop-in and sync /etc/vconsole.conf FONT (single value).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
font="${1:-default8x9}"
dropin_src="${repo_root}/ly/etc/systemd/system/ly@.service.d/setfont.conf"
dropin_dest="/etc/systemd/system/ly@.service.d/setfont.conf"
vconsole="/etc/vconsole.conf"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run with sudo: sudo bash ly/install-ly-font.sh [font]" >&2
  exit 1
fi

if ! setfont "${font}" </dev/null 2>/dev/null; then
  echo "Font not found: ${font} (see /usr/share/kbd/consolefonts/)" >&2
  exit 1
fi

install -d -m 755 /etc/systemd/system/ly@.service.d
sed "s|setfont default8x9|setfont ${font}|" "${dropin_src}" >"${dropin_dest}.tmp"
mv "${dropin_dest}.tmp" "${dropin_dest}"
chmod 644 "${dropin_dest}"

if [[ -f "${vconsole}" ]]; then
  sed -i '/^FONT=/d' "${vconsole}"
  printf 'FONT=%s\n' "${font}" >>"${vconsole}"
else
  printf 'FONT=%s\n' "${font}" >"${vconsole}"
fi

systemctl daemon-reload
systemctl restart systemd-vconsole-setup.service 2>/dev/null || true

mapfile -t ly_units < <(systemctl list-units --type=service --all 'ly@*.service' --no-legend 2>/dev/null | awk '{print $1}' || true)
if ((${#ly_units[@]} > 0)); then
  systemctl restart "${ly_units[@]}"
  echo "Restarted: ${ly_units[*]}"
fi

echo "Ly font set to ${font}. Switch to login VT (Ctrl+Alt+F1) to verify."
