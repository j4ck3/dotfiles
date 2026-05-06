#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

sudo_cmd=()
if [[ "${EUID}" -ne 0 ]]; then
  sudo_cmd=(sudo)
fi

"${sudo_cmd[@]}" install -Dm644 \
  "${repo_root}/etc/chromium/policies/managed/helium-managed.json" \
  /etc/chromium/policies/managed/helium-managed.json

"${sudo_cmd[@]}" install -Dm644 \
  "${repo_root}/etc/brave/policies/managed/brave-extensions.json" \
  /etc/brave/policies/managed/brave-extensions.json

printf '%s\n' \
  "Installed Chromium/Helium managed policy (search + forced extensions)." \
  "Installed Brave managed policy (forced extensions)." \
  "Restart browsers; check brave://policy or chrome://policy."
