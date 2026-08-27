#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
user="${SUDO_USER:-${USER}}"
target="${repo_root}/system/etc/sudoers.d/pacman"

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo bash "$0" "$@"
fi

groupadd -f pacman
usermod -aG pacman "${user}"

install -d /etc/sudoers.d
install -m 0440 "${target}" /etc/sudoers.d/pacman
visudo -cf /etc/sudoers.d/pacman

echo "Group pacman ready. User ${user} added."
echo "Re-login (or: newgrp pacman) so group membership applies."
echo "Then: sudo pacman -Syu  # no password"
