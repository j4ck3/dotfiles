#!/usr/bin/env bash
# One-time bootstrap: point libvirt + /usr/local/bin at ~/dotfiles/system.
# After this, edit the repo — changes are live. No stow re-run.
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  exec sudo -E bash "$0" "$@"
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
system_dir="${repo_root}/system"
hooks_src="${system_dir}/etc/libvirt/hooks"
bin_src="${system_dir}/usr/local/bin"

mkdir -p /etc/libvirt/hooks /usr/local/bin

ln -sfn "${hooks_src}/qemu" /etc/libvirt/hooks/qemu

# Marker checked by windows11-start / windows11-mode (not a stow artifact).
touch /etc/libvirt/hooks/windows11-gpu-passthrough.enabled
chmod 0644 /etc/libvirt/hooks/windows11-gpu-passthrough.enabled

shopt -s nullglob
for src in "${bin_src}"/windows11*; do
  base="$(basename "${src}")"
  ln -sfn "${src}" "/usr/local/bin/${base}"
done

echo "windows11 entrypoints → ${system_dir}"
echo "  hook: $(readlink -f /etc/libvirt/hooks/qemu)"
echo "  bin:  $(readlink -f /usr/local/bin/windows11-stealth-start)"
echo "Edit files under ${system_dir}; no reinstall needed."
