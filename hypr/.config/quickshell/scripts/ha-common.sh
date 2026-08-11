#!/bin/bash
# Shared Home Assistant auth for ha-light-*.sh (source only).
# shellcheck shell=bash

_ha_scripts_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "${_ha_scripts_dir}/ha.env"

HA_URL="${HA_URL:-http://10.0.0.23:8123}"
HA_ENTITY="${HA_ENTITY:-light.lifx_a19_4158ef}"
HA_TOKEN_FILE="${HA_TOKEN_FILE:-${HOME}/.config/homeassistant/token}"

ha_token() {
  if [[ ! -r "$HA_TOKEN_FILE" ]]; then
    return 1
  fi
  # Strip trailing newlines/spaces
  tr -d '\r\n' <"$HA_TOKEN_FILE" | sed 's/[[:space:]]*$//'
}

ha_auth_header() {
  local token
  token="$(ha_token)" || return 1
  [[ -n "$token" ]] || return 1
  printf 'Authorization: Bearer %s' "$token"
}

ha_curl() {
  # ha_curl METHOD PATH [curl -d args...]
  local method="$1"
  local path="$2"
  shift 2
  local auth
  auth="$(ha_auth_header)" || return 1
  curl -sS --connect-timeout 2 --max-time 5 \
    -X "$method" \
    -H "$auth" \
    -H "Content-Type: application/json" \
    "$@" \
    "${HA_URL}${path}"
}
