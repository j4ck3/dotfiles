#!/usr/bin/env bash
# Stow windows11-stealth helpers (usr/local/bin) + libvirt hooks (/etc).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${repo_root}/system/stow-system.sh"
