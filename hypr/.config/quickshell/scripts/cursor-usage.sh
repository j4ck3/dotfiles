#!/usr/bin/env bash
# Cursor plan usage for Quickshell bar.
#
# Reads session cookies from daily Helium
# (~/.config/net.imput.helium). No extra login profile.
#
# One-time:
#   ~/.config/quickshell/scripts/cursor-usage.sh setup
#   systemctl --user daemon-reload
#   systemctl --user enable --now qs-cursor-usage.timer
#
# Power menu: cursor-usage.sh status
# Open dashboard: cursor-usage.sh login
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")" && pwd)"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
CACHE="$CACHE_DIR/cursor-usage.json"
LOCK="$CACHE_DIR/cursor-usage.fetch.lock"
VENV="${CURSOR_USAGE_VENV:-$HOME/.config/qs-cursor/venv}"
PY="$VENV/bin/python"
HELIUM="${HELIUM_BROWSER:-$HOME/.local/bin/helium-browser}"
[[ -x "$HELIUM" ]] || HELIUM="/usr/bin/helium-browser"

cmd="${1:-status}"

emit() { printf '%s\n' "$1"; }

emit_cache() {
  local mode="${1:-status}"
  python3 - "$CACHE" "$mode" <<'PY'
import json, sys, time

path, mode = sys.argv[1], sys.argv[2]
try:
    with open(path, encoding="utf-8") as f:
        st = json.load(f)
except Exception:
    st = {}

display = (st.get("display") or "--").strip()
need_login = bool(st.get("need_login")) if st else True
ok = bool(st.get("ok"))
css = st.get("class") or ""
tip = st.get("tooltip") or ""
err = (st.get("error") or "").strip()
fetched = float(st.get("fetched_at") or 0)
age = time.time() - fetched if fetched else 0
stale = False

updated = ""
if fetched:
    local = time.localtime(fetched)
    now = time.localtime()
    if local[:3] == now[:3]:
        updated = time.strftime("updated %H:%M", local)
    else:
        updated = time.strftime("updated %Y-%m-%d %H:%M", local)

if not st:
    display = "--"
    css = "high"
    tip = "No cache yet"
    err = tip
elif need_login:
    display = "login"
    css = "high"
    tip = tip or "Log in to cursor.com in Helium"
elif not ok:
    display = display or "--"
    css = css or "high"
    if err:
        tip = (tip + "\n" if tip else "") + err

if age > 2700 and ok:
    stale = True
    css = css or "high"

out = {
    "ok": ok and not need_login,
    "need_login": need_login,
    "display": display,
    "models": st.get("models") or display,
    "other": st.get("other") or "",
    "on_demand": st.get("on_demand") or "",
    "updated": updated,
    "stale": stale,
    "error": err,
    "class": css,
    "tooltip": tip,
}

if mode == "bar":
    t = out["tooltip"]
    if updated:
        t = f"{updated}\n{t}" if t else updated
    if stale:
        t = f"STALE {int(age / 60)}m\n" + t
    text = "CURSOR\\n" + display.replace("\\", "\\\\").replace('"', '\\"')
    tip_s = (t or "Cursor usage").replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")
    print('{"text":"%s","tooltip":"%s","class":"%s"}' % (text, tip_s, css))
else:
    print(json.dumps(out, separators=(",", ":")))
PY
}

setup_venv() {
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q 'pycryptodomex>=3.20'
  echo "venv ready: $VENV" >&2
}

do_fetch() {
  mkdir -p "$CACHE_DIR"
  if [[ ! -x "$PY" ]]; then
    setup_venv
  fi
  export CURSOR_USAGE_CACHE="$CACHE"
  exec 9>"$LOCK"
  flock -n 9 || {
    echo "fetch already running" >&2
    return 0
  }
  "$PY" "$SCRIPT_DIR/cursor-usage-fetch.py"
}

do_login() {
  if [[ ! -x "$HELIUM" ]]; then
    echo "helium-browser not found" >&2
    exit 1
  fi
  exec "$HELIUM" "https://cursor.com/dashboard/usage"
}

case "$cmd" in
  bar) emit_cache bar ;;
  status|"") emit_cache status ;;
  setup) setup_venv ;;
  fetch) do_fetch ;;
  login|open) do_login ;;
  *)
    echo "usage: cursor-usage.sh [status|bar|setup|fetch|login]" >&2
    exit 2
    ;;
esac
