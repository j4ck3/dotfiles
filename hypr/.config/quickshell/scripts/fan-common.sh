#!/bin/bash
# Shared CoolerControl auth for fan-*.sh (source only).
# shellcheck shell=bash

CC_URL="${CC_URL:-https://127.0.0.1:11987}"
CC_TOKEN_FILE="${CC_TOKEN_FILE:-${HOME}/.config/coolercontrol/token}"
# nct6798 on this machine
CC_NCT_UID="${CC_NCT_UID:-00a4da18625f56275c89e2fcd25a83c08c5ad3326452fa7e252fcc8a89c92493}"
# Case Balanced mix profile (fan4/7 default)
CC_CASE_PROFILE_UID="${CC_CASE_PROFILE_UID:-b2c3d4e5-f6a7-8901-bcde-f12345678903}"
# CPU fan header/profile.
CC_CPU_FAN="${CC_CPU_FAN:-fan5}"
CC_CPU_PROFILE_UID="${CC_CPU_PROFILE_UID:-b2c3d4e5-f6a7-8901-bcde-f12345678901}"
# Controllable case headers.
CC_CASE_FANS="${CC_CASE_FANS:-fan4 fan6 fan7}"

cc_token() {
  if [[ ! -r "$CC_TOKEN_FILE" ]]; then
    return 1
  fi
  tr -d '\r\n' <"$CC_TOKEN_FILE" | sed 's/[[:space:]]*$//'
}

cc_auth_header() {
  local token
  token="$(cc_token)" || return 1
  [[ -n "$token" ]] || return 1
  printf 'Authorization: Bearer %s' "$token"
}

cc_curl() {
  # cc_curl METHOD PATH [extra curl args...]
  local method="$1"
  local path="$2"
  shift 2
  local auth
  auth="$(cc_auth_header)" || return 1
  curl -sS -k --connect-timeout 1 --max-time 3 \
    -X "$method" \
    -H "$auth" \
    -H "Content-Type: application/json" \
    "$@" \
    "${CC_URL}${path}"
}
