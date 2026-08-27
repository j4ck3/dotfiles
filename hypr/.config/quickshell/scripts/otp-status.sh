#!/usr/bin/env bash
# Quickshell bar: show last OTP while chip TTL active.
set -euo pipefail

readonly STATE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell/otp-watch.json"

emit() {
  printf '%s\n' "$1"
}

if [[ ! -f "$STATE_FILE" ]]; then
  emit '{"text":"","tooltip":"","class":"hidden"}'
  exit 0
fi

python3 - "$STATE_FILE" <<'PY'
import json, sys, time

path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        st = json.load(f)
except Exception:
    print('{"text":"","tooltip":"","class":"hidden"}')
    raise SystemExit(0)

now = time.time()
code = (st.get("code") or "").strip()
expires = float(st.get("expires_at") or 0)
frm = (st.get("from") or "").strip()
mode = st.get("mode") or "idle"
err = (st.get("error") or "").strip()

if code and expires > now:
    tip = f"OTP from {frm} — click to copy" if frm else "OTP — click to copy"
    # Escape for JSON string (JsonScript wants \\n in the JSON text field).
    text = f"OTP\\n{code}"
    print(
        '{"text":"%s","tooltip":"%s","class":"active"}'
        % (text, tip.replace("\\", "\\\\").replace('"', '\\"'))
    )
    raise SystemExit(0)

if mode == "armed":
    tip = "Watching inbox for OTP…"
    if err:
        tip = err[:80]
    print(
        '{"text":"OTP\\n…","tooltip":"%s","class":"high"}'
        % tip.replace("\\", "\\\\").replace('"', '\\"')
    )
    raise SystemExit(0)

print('{"text":"","tooltip":"","class":"hidden"}')
PY
