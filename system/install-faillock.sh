#!/usr/bin/env bash
# Symlink faillock.conf into /etc via stow.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
target=/etc/security/faillock.conf
tracked="${repo}/faillock/etc/security/faillock.conf"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
  fi
}

need_root

if [[ -f "${target}" && ! -L "${target}" ]]; then
  if ! diff -q "${tracked}" "${target}" >/dev/null 2>&1; then
    backup="${target}.pre-stow.$(date +%Y%m%d%H%M%S)"
    echo "Backing up ${target} -> ${backup}"
    cp -a "${target}" "${backup}"
  fi
  rm -f "${target}"
fi

exec stow -v -R -t / -d "${repo}" faillock
