#!/usr/bin/env bash
# Route netbird.hjacke.com to local Traefik (10.0.0.25), bypassing Cloudflare gRPC blocks.
set -euo pipefail

LINE='10.0.0.25 netbird.hjacke.com'
HOSTS=/etc/hosts

if [[ "$(id -u)" -ne 0 ]]; then
  exec sudo "$0" "$@"
fi

if grep -qF 'netbird.hjacke.com' "$HOSTS"; then
  if grep -qF "$LINE" "$HOSTS"; then
    echo "OK: $LINE already in $HOSTS"
  else
    echo "WARN: netbird.hjacke.com present in $HOSTS but not as expected:" >&2
    grep 'netbird.hjacke.com' "$HOSTS" >&2 || true
    echo "Fix manually or remove the old line, then re-run." >&2
    exit 1
  fi
else
  printf '\n# NetBird management (LAN Traefik; Cloudflare blocks gRPC)\n%s\n' "$LINE" >>"$HOSTS"
  echo "Added: $LINE"
fi

if command -v resolvectl >/dev/null; then
  resolvectl flush-caches 2>/dev/null || true
  systemctl try-reload-or-restart systemd-resolved 2>/dev/null || true
fi

if getent ahostsv4 netbird.hjacke.com 2>/dev/null | awk '{print $1}' | grep -qxF '10.0.0.25'; then
  echo "OK: netbird.hjacke.com -> 10.0.0.25 (IPv4)"
else
  echo "WARN: netbird.hjacke.com still not 10.0.0.25 (IPv4) after hosts update:" >&2
  getent hosts netbird.hjacke.com >&2 || true
  echo >&2
  echo "If this persists, add Pi-hole local DNS (10.0.0.53 admin):" >&2
  echo "  netbird.hjacke.com -> 10.0.0.25" >&2
  exit 1
fi
