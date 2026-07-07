#!/usr/bin/env bash
# Latest Ly TTY size from ly.log (character cells, not pixels).
# Usage: ly/scripts/ly-tty-size.sh  -> 430x160
set -euo pipefail

log="${LY_LOG:-/var/log/ly.log}"
if [[ ! -r "${log}" ]]; then
  echo "ly-tty-size: cannot read ${log}" >&2
  exit 1
fi

line="$(rg 'screen resolution' "${log}" 2>/dev/null | tail -1 || true)"
if [[ -z "${line}" ]]; then
  echo "ly-tty-size: no resolution in ${log} (visit login VT once)" >&2
  exit 1
fi

if [[ "${line}" =~ is[[:space:]]+([0-9]+)x([0-9]+) ]]; then
  printf '%sx%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
elif [[ "${line}" =~ updated[[:space:]]+to[[:space:]]+([0-9]+)x([0-9]+) ]]; then
  printf '%sx%s\n' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
else
  echo "ly-tty-size: could not parse: ${line}" >&2
  exit 1
fi
