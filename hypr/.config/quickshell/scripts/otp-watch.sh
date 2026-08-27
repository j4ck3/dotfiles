#!/usr/bin/env bash
# Control Outlook OTP watcher used by Quickshell PowerMenu / bar.
# Commands: arm | disarm | toggle | status | login | copy | ensure
set -euo pipefail

_scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/quickshell"
readonly STATE_FILE="${STATE_DIR}/otp-watch.json"
readonly DAEMON="${_scripts_dir}/otp-watchd.py"
readonly CHIP_TTL=60
readonly OTP_VENV_PY="${HOME}/.config/qs-otp/venv/bin/python"

otp_python() {
  if [[ -x "$OTP_VENV_PY" ]]; then
    printf '%s\n' "$OTP_VENV_PY"
  else
    printf '%s\n' "python3"
  fi
}

mkdir -p "$STATE_DIR"

default_json() {
  printf '%s\n' '{"mode":"idle","armed_at":0,"code":"","from":"","subject":"","found_at":0,"expires_at":0,"ok":true,"error":""}'
}

ensure_state() {
  if [[ ! -f "$STATE_FILE" ]]; then
    default_json >"$STATE_FILE"
  fi
}

read_json() {
  ensure_state
  cat "$STATE_FILE"
}

# Merge keys into state via python (atomic).
patch_state() {
  python3 - "$STATE_FILE" "$@" <<'PY'
import json, os, sys, tempfile, time

path = sys.argv[1]
args = sys.argv[2:]
try:
    with open(path, encoding="utf-8") as f:
        st = json.load(f)
except Exception:
    st = {
        "mode": "idle", "armed_at": 0, "code": "", "from": "", "subject": "",
        "found_at": 0, "expires_at": 0, "ok": True, "error": "",
    }

i = 0
while i < len(args):
    k = args[i]
    if k == "--arm":
        st["mode"] = "armed"
        st["armed_at"] = time.time()
        st["error"] = ""
        st["ok"] = True
        i += 1
        continue
    if k == "--disarm":
        st["mode"] = "idle"
        i += 1
        continue
    if k.startswith("--") and i + 1 < len(args):
        key = k[2:]
        val = args[i + 1]
        if key in ("armed_at", "found_at", "expires_at"):
            st[key] = float(val)
        elif key == "ok":
            st[key] = val.lower() in ("1", "true", "yes")
        else:
            st[key] = val
        i += 2
        continue
    i += 1

fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".otp-", suffix=".tmp")
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(st, f, ensure_ascii=False)
    f.write("\n")
    f.flush()
    os.fsync(f.fileno())
os.replace(tmp, path)
print(json.dumps(st, ensure_ascii=False))
PY
}

cmd_status() {
  ensure_state
  # Enrich with derived fields for PowerMenu.
  python3 - "$STATE_FILE" <<'PY'
import json, sys, time
path = sys.argv[1]
try:
    with open(path, encoding="utf-8") as f:
        st = json.load(f)
except Exception:
    st = {"mode": "idle", "ok": False, "error": "bad state"}

now = time.time()
mode = st.get("mode") or "idle"
armed_at = float(st.get("armed_at") or 0)
expires = float(st.get("expires_at") or 0)
code = st.get("code") or ""
has_chip = bool(code) and expires > now
armed_left = max(0, int(5 * 60 - (now - armed_at))) if mode == "armed" and armed_at else 0

st["has_chip"] = has_chip
st["armed_left"] = armed_left
st["watching"] = mode == "armed"
print(json.dumps(st, ensure_ascii=False))
PY
}

cmd_arm() {
  patch_state --arm >/dev/null
  cmd_status
}

cmd_disarm() {
  patch_state --disarm >/dev/null
  cmd_status
}

cmd_toggle() {
  ensure_state
  mode=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("mode","idle"))' "$STATE_FILE")
  if [[ "$mode" == "armed" ]]; then
    cmd_disarm
  else
    cmd_arm
  fi
}

cmd_copy() {
  ensure_state
  code=$(python3 -c 'import json,sys,time; s=json.load(open(sys.argv[1])); c=s.get("code") or ""; e=float(s.get("expires_at") or 0); print(c if c and e>time.time() else "")' "$STATE_FILE")
  if [[ -z "$code" ]]; then
    exit 1
  fi
  printf '%s' "$code" | wl-copy --
}

cmd_login() {
  exec "$(otp_python)" "$DAEMON" --login
}

cmd_ensure() {
  # Best-effort: start user unit if present.
  if systemctl --user cat qs-otp-watchd.service >/dev/null 2>&1; then
    systemctl --user start qs-otp-watchd.service 2>/dev/null || true
  fi
}

usage() {
  cat <<EOF
usage: $(basename "$0") arm|disarm|toggle|status|login|copy|ensure
EOF
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    arm) cmd_arm ;;
    disarm) cmd_disarm ;;
    toggle) cmd_toggle ;;
    status) cmd_status ;;
    login) cmd_login ;;
    copy) cmd_copy ;;
    ensure) cmd_ensure ;;
    *) usage; exit 2 ;;
  esac
}

main "$@"
