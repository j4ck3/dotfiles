#!/usr/bin/env bash
set -euo pipefail

AGENT_DIR="${PI_AGENT_DIR:-$HOME/.pi/agent}"
EXT="$AGENT_DIR/extensions"

install_npm_ext() {
  local dir="$1"
  if [[ -f "$dir/package.json" ]]; then
    echo "npm install --ignore-scripts in $dir"
    (cd "$dir" && npm install --ignore-scripts)
  fi
}

for ext in bash-guard browser web-fetch; do
  install_npm_ext "$EXT/$ext"
done

if [[ -d "$EXT/browser" ]]; then
  echo "playwright install chromium (for browser extension)"
  (cd "$EXT/browser" && npm exec -- playwright install chromium)
fi

PDF_SKILL="$AGENT_DIR/skills/pdf-reader"
if [[ -d "$PDF_SKILL" && -f "$PDF_SKILL/requirements.txt" ]]; then
  VENV="$PDF_SKILL/.venv"
  if [[ ! -x "$VENV/bin/python" ]]; then
    echo "creating pdf-reader venv at $VENV"
    python3 -m venv "$VENV"
  fi
  "$VENV/bin/pip" install -r "$PDF_SKILL/requirements.txt"
fi

echo "done. optional system tools: yt-dlp ffmpeg (youtube-transcript skill)"
