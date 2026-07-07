#!/usr/bin/env bash
# Rebuild fractal-ascii.dur to match current Ly TTY size, then install.
# This is needed for 21:9/ultrawide setups because Ly does not scale .dur files.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
size="$("${repo_root}/ly/scripts/ly-tty-size.sh")"
width="${size%x*}"
height="${size#*x}"

echo "Ly TTY: ${width}x${height} - rebuilding full-screen fractal-ascii.dur"

if [[ ! -d /tmp/durdraw ]]; then
  git clone --depth 1 https://github.com/cmang/durdraw.git /tmp/durdraw
fi

python3 "${repo_root}/ly/scripts/video-to-dur.py" \
  "${repo_root}/ly/assets/fractal-ascii-preview.webm" \
  --width "${width}" --height "${height}" \
  --style solid --capture-fps 30 --loop-sec 30 \
  --blur 1.0 --temporal 0.45 --luma-threshold 85

if [[ "$(id -u)" -eq 0 ]]; then
  bash "${repo_root}/ly/install-ly-background.sh" fractal-ascii.dur
else
  echo "Run: sudo bash ly/install-ly-background.sh fractal-ascii.dur"
fi
