#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

install -d /etc/X11/xorg.conf.d
install -d /usr/local/share/kbd/keymaps

install -m 0644 "${repo_root}/system/etc/X11/xorg.conf.d/00-keyboard.conf" /etc/X11/xorg.conf.d/00-keyboard.conf
install -m 0644 "${repo_root}/system/etc/vconsole.conf" /etc/vconsole.conf
install -m 0644 "${repo_root}/system/usr/local/share/kbd/keymaps/capsescape.map" /usr/local/share/kbd/keymaps/capsescape.map

echo 'Caps Lock -> Escape installed for Linux (X11 + virtual console).'
echo 'Reboot or restart your graphical session for XKB changes to apply.'
