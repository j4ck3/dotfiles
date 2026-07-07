#!/usr/bin/env bash
# Stow system/ to / (symlink usr/local/bin, /etc/libvirt, udev rules, ...).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
system_dir="${repo_root}/system"

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

# Removed from repo; drop stale copy-install leftovers.
rm -f /usr/local/bin/windows11-stealth-{boot-probe,recover-boot,resize-disk,restore-nvram,add-soundblaster}

# Stow needs symlink targets; remove plain files at /etc and /usr paths repo will own.
while IFS= read -r -d '' path; do
  rel="${path#${system_dir}/}"
  [[ "${rel}" == "${path}" || "${rel}" == *".."* ]] && continue
  target="/${rel}"
  [[ "${target}" == "${system_dir}"* ]] && continue
  [[ -e "${target}" && ! -L "${target}" ]] || continue
  rm -rf "${target}"
done < <(find "${system_dir}/etc" "${system_dir}/usr" -type f -print0)

cd "${repo_root}"
stow -v -R -t / system

touch /etc/libvirt/hooks/windows11-gpu-passthrough.enabled
chmod 0644 /etc/libvirt/hooks/windows11-gpu-passthrough.enabled

echo ""
echo "Stowed ${system_dir} -> /"
echo "  bin:  ls -l /usr/local/bin/windows11-stealth-start"
echo "  hook: ls -l /etc/libvirt/windows11/gpu-handoff.sh"
echo "Log: /var/log/windows11-passthrough-hook.log"

if ! grep -q 'restore_hyprland_session' /etc/libvirt/windows11/gpu-handoff.sh; then
  echo "WARN: gpu-handoff install verification failed" >&2
  exit 1
fi
