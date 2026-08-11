#!/bin/bash
# Temporary case-fan override (fan4/5/7) via CoolerControl.
# usage: fan-control.sh set <0-100>
#        fan-control.sh auto          # restore Case Balanced curve
set -euo pipefail

_scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_scripts_dir}/fan-common.sh"

LOCK_FILE="${XDG_RUNTIME_DIR:-/tmp}/qs-fan.lock"

usage() {
  echo "usage: $0 <set|auto> [duty]" >&2
  exit 1
}

[[ $# -ge 1 ]] || usage
action=$1
value=${2:-}

exec 9>"$LOCK_FILE"
flock -w 2 9 || exit 0

auth="$(cc_auth_header)" || exit 1

set_fixed() {
  local duty=$1
  local fan
  for fan in $CC_CASE_FANS; do
    cc_curl PUT \
      "/devices/${CC_NCT_UID}/settings/${fan}/manual" \
      -d "{\"speed_fixed\": ${duty}}" >/dev/null \
      || true
  done
}

restore_auto() {
  local fan
  for fan in $CC_CASE_FANS; do
    cc_curl PUT \
      "/devices/${CC_NCT_UID}/settings/${fan}/profile" \
      -d "{\"profile_uid\": \"${CC_CASE_PROFILE_UID}\"}" >/dev/null \
      || true
  done
}

case "$action" in
  set)
    [[ -n "$value" ]] || usage
    duty=${value%.*}
    if (( duty < 0 )); then duty=0; fi
    if (( duty > 100 )); then duty=100; fi
    set_fixed "$duty"
    ;;
  auto)
    restore_auto
    ;;
  *)
    usage
    ;;
esac
