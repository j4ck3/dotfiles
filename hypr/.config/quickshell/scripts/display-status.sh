#!/bin/bash
# Status for quickshell BRT widget / DisplayPopup (screen_shader backend).
set -euo pipefail

STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/qs-display.state"
SHADER_OPT=$(hyprctl getoption decoration:screen_shader -j 2>/dev/null || true)

gamma=100
temp=6500
identity=true
if [[ -f "$STATE_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$STATE_FILE" 2>/dev/null || true
fi
gamma=${gamma:-100}
temp=${temp:-6500}
identity=${identity:-true}

running=true
# If hyprctl missing, still report state file.
if ! command -v hyprctl >/dev/null 2>&1; then
  running=false
fi

if [[ "$identity" == "true" ]]; then
  value="${gamma}%"
  class=""
  tip="Brightness ${gamma}% · night light off"
else
  value="NITE"
  class="active"
  tip="Brightness ${gamma}% · ${temp}K"
fi

# JSON bool
id_json=false
[[ "$identity" == "true" ]] && id_json=true

printf '{"gamma":%s,"temp":%s,"identity":%s,"running":%s,"backend":"shader","text":"BRT\\n%s","tooltip":"%s","class":"%s"}\n' \
  "$gamma" "$temp" "$id_json" "$running" "$value" "$tip" "$class"
