#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

sudo_cmd=()
if [[ "${EUID}" -ne 0 ]]; then
  sudo_cmd=(sudo)
fi

"${sudo_cmd[@]}" install -Dm644 \
  "${repo_root}/etc/X11/xorg.conf.d/00-keyboard.conf" \
  /etc/X11/xorg.conf.d/00-keyboard.conf

"${sudo_cmd[@]}" install -Dm644 \
  "${repo_root}/usr/local/share/kbd/keymaps/capsescape.map" \
  /usr/local/share/kbd/keymaps/capsescape.map

"${sudo_cmd[@]}" install -Dm644 \
  "${repo_root}/etc/vconsole.conf" \
  /etc/vconsole.conf

printf '%s\n' \
  "Installed CapsLock -> Escape for XKB and Linux virtual consoles." \
  "Restart your session or reboot to pick up both layers." \
  "To test the TTY mapping immediately in the current console, run: sudo loadkeys /usr/local/share/kbd/keymaps/capsescape.map"
