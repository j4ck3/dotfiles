#!/bin/bash
# Case fans (fan4/6/7) status for PowerMenu slider.
# JSON: {ok, override, duty, rpm, fans:[{name,duty,rpm,override}]}
set -euo pipefail

_scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_scripts_dir}/fan-common.sh"

fail_json() {
  printf '{"ok":false,"override":false,"duty":0,"rpm":0,"fans":[],"error":"%s"}\n' "$1"
  exit 0
}

auth="$(cc_auth_header)" || fail_json "no_token"

settings_raw="$(cc_curl GET "/devices/${CC_NCT_UID}/settings" 2>/dev/null)" \
  || fail_json "settings"
status_raw="$(cc_curl GET "/status" 2>/dev/null)" \
  || fail_json "status"

python3 - "$CC_CASE_FANS" "$settings_raw" "$status_raw" "$CC_NCT_UID" <<'PY'
import json, sys

fans = sys.argv[1].split()
try:
    settings = json.loads(sys.argv[2])
    status = json.loads(sys.argv[3])
except Exception:
    print('{"ok":false,"override":false,"duty":0,"rpm":0,"fans":[],"error":"parse"}')
    raise SystemExit(0)

uid = sys.argv[4]
settings_by = {}
for s in settings.get("settings") or []:
    settings_by[s.get("channel_name")] = s

# Latest history sample for nct device
channels = {}
for dev in status.get("devices") or []:
    if dev.get("uid") != uid:
        continue
    hist = dev.get("status_history") or []
    if not hist:
        break
    for ch in hist[-1].get("channels") or []:
        channels[ch.get("name")] = ch
    break

out_fans = []
duties = []
rpms = []
any_override = False
for name in fans:
    st = settings_by.get(name) or {}
    ch = channels.get(name) or {}
    fixed = st.get("speed_fixed")
    override = fixed is not None
    if override:
        any_override = True
        duty = int(round(float(fixed)))
    else:
        d = ch.get("duty")
        duty = int(round(float(d))) if d is not None else 0
    rpm = int(ch.get("rpm") or 0)
    duties.append(duty)
    rpms.append(rpm)
    out_fans.append({
        "name": name,
        "duty": duty,
        "rpm": rpm,
        "override": override,
    })

avg_duty = int(round(sum(duties) / len(duties))) if duties else 0
avg_rpm = int(round(sum(rpms) / len(rpms))) if rpms else 0
print(json.dumps({
    "ok": True,
    "override": any_override,
    "duty": avg_duty,
    "rpm": avg_rpm,
    "fans": out_fans,
}))
PY
