#!/usr/bin/env bash
# Deploy windows11-stealth libvirt qemu.d hooks + GPU handoff (host restore after VM).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${repo_root}/system/stow-system.sh"
