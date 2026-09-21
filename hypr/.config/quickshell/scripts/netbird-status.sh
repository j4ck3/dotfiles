#!/usr/bin/env bash
# NetBird status / toggle for Quickshell PowerMenu.
# Commands: status | up | down | toggle
set -euo pipefail

cmd="${1:-status}"

fail_json() {
  local msg="${1:-unavailable}"
  msg="${msg//\\/\\\\}"
  msg="${msg//\"/\\\"}"
  printf '{"ok":false,"connected":false,"display":"Offline","ip":"","fqdn":"","host":"","peers_connected":0,"peers_total":0,"management":false,"signal":false,"relays":"0/0","error":"%s"}\n' "$msg"
  exit 0
}

if ! command -v netbird >/dev/null 2>&1; then
  fail_json "netbird missing"
fi

MGMT_URL="${NETBIRD_MGMT_URL:-https://netbird.hjacke.com:443}"
nb_up() { netbird up --management-url "$MGMT_URL" --disable-dns >/dev/null 2>&1 || true; }

is_connected() {
  local raw
  raw="$(netbird status --json 2>/dev/null)" || return 1
  printf '%s' "$raw" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)
mgmt = (d.get("management") or {}).get("connected")
daemon = (d.get("daemonStatus") or "") == "Connected"
ip = ((d.get("netbirdIp") or "").split("/")[0])
raise SystemExit(0 if daemon and (mgmt or ip) else 1)
' 2>/dev/null
}

case "$cmd" in
  status) ;;
  up)
    nb_up
    ;;
  down)
    netbird down >/dev/null 2>&1 || true
    ;;
  toggle)
    if is_connected; then
      netbird down >/dev/null 2>&1 || true
    else
      nb_up
    fi
    ;;
  *)
    fail_json "bad cmd"
    ;;
esac

raw="$(netbird status --json 2>/dev/null)" || fail_json "daemon unreachable"
[[ -n "$raw" ]] || fail_json "empty status"

printf '%s' "$raw" | python3 -c '
import json, sys

try:
    d = json.load(sys.stdin)
except Exception:
    print(json.dumps({
        "ok": False, "connected": False, "display": "Offline",
        "ip": "", "fqdn": "", "host": "",
        "peers_connected": 0, "peers_total": 0,
        "management": False, "signal": False, "relays": "0/0",
        "error": "parse",
    }, separators=(",", ":")))
    raise SystemExit(0)

mgmt = bool((d.get("management") or {}).get("connected"))
sig = bool((d.get("signal") or {}).get("connected"))
daemon = (d.get("daemonStatus") or "") == "Connected"

ip_raw = d.get("netbirdIp") or ""
ip = ip_raw.split("/", 1)[0] if ip_raw else ""
connected = daemon and (mgmt or bool(ip))

fqdn = d.get("fqdn") or ""
host = fqdn.split(".", 1)[0] if fqdn else ""

peers = d.get("peers") or {}
pc = int(peers.get("connected") or 0)
pt = int(peers.get("total") or 0)

relays = d.get("relays") or {}
ra = int(relays.get("available") or 0)
rt = int(relays.get("total") or 0)

err = ""
if not connected:
    err = ((d.get("management") or {}).get("error")
           or (d.get("signal") or {}).get("error")
           or (d.get("daemonStatus") or "Disconnected"))

display = "Connected" if connected else "Disconnected"

out = {
    "ok": True,
    "connected": connected,
    "display": display,
    "ip": ip,
    "fqdn": fqdn,
    "host": host,
    "peers_connected": pc,
    "peers_total": pt,
    "management": mgmt,
    "signal": sig,
    "relays": f"{ra}/{rt}",
    "error": err,
}
print(json.dumps(out, separators=(",", ":")))
'
