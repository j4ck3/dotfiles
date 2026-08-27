#!/bin/bash
# Cycle nct6798 PWM headers one at a time so you can map fan4/5/6/7 to physical fans.
#
# Run:
#   ~/dotfiles/hypr/.config/quickshell/scripts/fan-identify.sh
#   ~/dotfiles/hypr/.config/quickshell/scripts/fan-identify.sh --auto
#   ~/dotfiles/hypr/.config/quickshell/scripts/fan-identify.sh fan4 fan5
#
# Logs append to ~/.local/state/fan-identify.log (override: FAN_IDENTIFY_LOG=path).
# Restores prior CoolerControl settings when done (or Ctrl+C).
set -euo pipefail

_scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_scripts_dir}/fan-common.sh"

HWMON="${CC_HWMON:-/sys/class/hwmon/hwmon3}"
DEFAULT_FANS=(fan4 fan5 fan6 fan7)
AUTO=false
FANS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto) AUTO=true; shift ;;
    -h|--help)
      sed -n '2,5p' "$0" | sed 's/^# \?//'
      exit 0
      ;;
    fan[0-9]*) FANS+=("$1"); shift ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ ${#FANS[@]} -gt 0 ]] || FANS=("${DEFAULT_FANS[@]}")

LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/qs-fan.lock"
STATE_FILE="${XDG_RUNTIME_DIR:-/tmp}/qs-fan-identify-state.json"
LOG_FILE="${FAN_IDENTIFY_LOG:-${HOME}/.local/state/fan-identify.log}"
RESTORED=false
SPIN_RPM_MIN="${FAN_IDENTIFY_SPIN_RPM:-200}"

cc_auth_header >/dev/null || {
  echo "need readable token: $CC_TOKEN_FILE" >&2
  exit 1
}

read_rpm() {
  local fan=$1
  local path="${HWMON}/${fan}_input"
  [[ -r "$path" ]] || { echo 0; return; }
  tr -d '\n' <"$path"
}

save_state() {
  cc_curl GET "/devices/${CC_NCT_UID}/settings" >"$STATE_FILE"
}

set_manual() {
  local fan=$1
  local duty=$2
  cc_curl PUT \
    "/devices/${CC_NCT_UID}/settings/${fan}/manual" \
    -d "{\"speed_fixed\": ${duty}}" >/dev/null \
    || true
}

restore_profile() {
  local fan=$1
  local uid=$2
  cc_curl PUT \
    "/devices/${CC_NCT_UID}/settings/${fan}/profile" \
    -d "{\"profile_uid\": \"${uid}\"}" >/dev/null \
    || true
}

restore_state() {
  [[ "$RESTORED" == true ]] && return 0
  RESTORED=true
  [[ -f "$STATE_FILE" ]] || return 0

  python3 - "$STATE_FILE" "$CC_CASE_PROFILE_UID" <<'PY' | while read -r fan kind value; do
import json, sys

path, case_uid = sys.argv[1], sys.argv[2]
with open(path, encoding="utf-8") as f:
    data = json.load(f)

for st in data.get("settings") or []:
    name = st.get("channel_name")
    if not name or not name.startswith("fan"):
        continue
    fixed = st.get("speed_fixed")
    profile = st.get("profile_uid")
    if fixed is not None:
        print(name, "fixed", int(round(float(fixed))))
    elif profile:
        print(name, "profile", profile)
    elif name in {"fan4", "fan5", "fan6", "fan7"}:
        print(name, "profile", case_uid)
PY
    case "$kind" in
      fixed) set_manual "$fan" "$value" ;;
      profile) restore_profile "$fan" "$value" ;;
    esac
  done
  rm -f "$STATE_FILE"
}

cleanup() {
  restore_state
}
trap cleanup EXIT INT TERM

exec 9>"$LOCK_FILE"
flock -w 5 9 || {
  echo "another fan script holds $LOCK_FILE" >&2
  exit 1
}

save_state

echo "Fan header identify — open case, note which physical fan spins for each header."
echo "Headers: ${FANS[*]}"
echo

log_duties() {
  local target=$1
  for fan in fan4 fan5 fan6 fan7; do
    local duty=0
    [[ "$fan" == "$target" ]] && duty=100
    echo "  set ${fan} -> ${duty}%"
  done
}

for target in "${FANS[@]}"; do
  echo
  echo "========================================"
  echo "  TESTING: ${target} @ 100% PWM"
  echo "  (all other case headers forced to 0%)"
  echo "========================================"
  for fan in fan4 fan5 fan6 fan7; do
    duty=0
    [[ "$fan" == "$target" ]] && duty=100
    set_manual "$fan" "$duty"
  done
  log_duties "$target"

  sleep 2
  for _ in 1 2 3 4 5 6; do
    echo -n "  RPM @100=${target}:"
    for fan in fan4 fan5 fan6 fan7; do
      rpm="$(read_rpm "$fan")"
      if [[ "$fan" == "$target" ]]; then
        printf ' **%s=%s**' "$fan" "$rpm"
      else
        printf ' %s=%s' "$fan" "$rpm"
      fi
    done
    echo
    sleep 1
  done

  if [[ "$AUTO" == true ]]; then
    sleep 2
  else
    read -r -p "Which physical fan spun up? (Enter for next, q to quit) " ans || true
    [[ "${ans:-}" == "q" ]] && break
  fi
  echo
done

echo "Done. Restoring prior fan settings."
