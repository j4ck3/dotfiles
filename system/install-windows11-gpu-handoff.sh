#!/usr/bin/env bash
# Stow libvirt GPU handoff + qemu.d hooks under /etc/libvirt.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${repo_root}/system/stow-system.sh"
