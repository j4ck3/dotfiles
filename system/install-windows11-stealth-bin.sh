#!/usr/bin/env bash
# Deprecated wrapper — windows11 is live from the repo (see ensure-windows11-live.sh).
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${repo_root}/system/ensure-windows11-live.sh"
