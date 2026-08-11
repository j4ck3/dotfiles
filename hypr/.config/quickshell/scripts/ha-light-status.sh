#!/bin/bash
# JSON status for PowerMenu HA light slider / hue wheel.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${SCRIPT_DIR}/ha-common.sh"

fail_json() {
  printf '{"ok":false,"on":false,"brightness":0,"hue":0,"sat":0,"name":"?"}\n'
  exit 0
}

raw="$(ha_curl GET "/api/states/${HA_ENTITY}" 2>/dev/null)" || fail_json
[[ -n "$raw" ]] || fail_json

if ! command -v jq >/dev/null 2>&1; then
  fail_json
fi

parsed="$(printf '%s' "$raw" | jq -c '
  if type != "object" or (.entity_id|not) then
    empty
  else
    {
      ok: true,
      on: (.state == "on"),
      brightness: (
        if .state == "on" and (.attributes.brightness|type) == "number" then
          ((.attributes.brightness / 255 * 100) + 0.5 | floor)
        else
          0
        end
      ),
      hue: (
        if (.attributes.hs_color|type) == "array" and (.attributes.hs_color|length) >= 2 then
          (.attributes.hs_color[0] // 0)
        else
          0
        end
      ),
      sat: (
        if (.attributes.hs_color|type) == "array" and (.attributes.hs_color|length) >= 2 then
          (.attributes.hs_color[1] // 0)
        else
          0
        end
      ),
      name: (.attributes.friendly_name // .entity_id // "?")
    }
  end
' 2>/dev/null)" || fail_json

[[ -n "$parsed" ]] || fail_json
printf '%s\n' "$parsed"
