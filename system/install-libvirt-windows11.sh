#!/usr/bin/env bash
# Install windows11 KVM helpers, VFIO-Tools hooks, and libvirt fragments system-wide.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
etc_dir="/etc/libvirt/windows11"
bin_dir="/usr/local/bin"
hooks_base="/etc/libvirt/hooks"
hooks_dst="${hooks_base}/qemu.d/windows11"
enable_file="${hooks_base}/windows11-gpu-passthrough.enabled"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

install -d -m 0755 "${etc_dir}" /var/lib/libvirt/vbios "${hooks_base}"
if [[ -f /etc/libvirt/vbios/rx7900xtx.rom && ! -f /var/lib/libvirt/vbios/rx7900xtx.rom ]]; then
  install -m 0644 /etc/libvirt/vbios/rx7900xtx.rom /var/lib/libvirt/vbios/
fi
chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/vbios 2>/dev/null || true
install -m 0644 "${repo}/etc/libvirt/windows11-amd-gpu-hostdev.xml" "${etc_dir}/"
install -m 0644 "${repo}/etc/libvirt/windows11-passthrough-usb.xml" "${etc_dir}/"
install -m 0644 "${repo}/etc/libvirt/windows11/hook-log.sh" "${etc_dir}/hook-log.sh"
install -m 0644 "${repo}/etc/libvirt/windows11/gpu-handoff.conf" "${etc_dir}/gpu-handoff.conf"
install -m 0644 "${repo}/etc/libvirt/windows11/gpu-handoff.sh" "${etc_dir}/gpu-handoff.sh"
install -m 0755 "${repo}/etc/libvirt/windows11/patch-domain.py" "${etc_dir}/patch-domain.py"
install -m 0644 "${repo}/etc/modprobe.d/vfio-windows11.conf" /etc/modprobe.d/vfio-windows11.conf

touch /var/log/windows11-passthrough-hook.log
chmod 0644 /var/log/windows11-passthrough-hook.log

for cmd in windows11-mode windows11-console windows11-stop windows11-force-stop \
  windows11-revert-host windows11-unstick windows11-start windows11-network \
  windows11-disk windows11-dump-vbios windows11-watchdog-cancel windows11-watchdog-revert \
  windows11-passthrough-doctor windows11-tools-iso vfio-limine-enable; do
  install -m 0755 "${repo}/usr/local/bin/${cmd}" "${bin_dir}/${cmd}"
done

install -m 0755 "${repo}/etc/libvirt/hooks/qemu" "${hooks_base}/qemu"
install -d -m 0755 "${hooks_dst}/prepare/begin" "${hooks_dst}/release/end"
install -m 0755 "${repo}/etc/libvirt/hooks/qemu.d/windows11/prepare/begin/start.sh" \
  "${hooks_dst}/prepare/begin/start.sh"
install -m 0755 "${repo}/etc/libvirt/hooks/qemu.d/windows11/release/end/revert.sh" \
  "${hooks_dst}/release/end/revert.sh"

systemctl restart libvirtd.service 2>/dev/null || true

echo "Installed."
echo ""
echo "VFIO-Tools hooks:"
echo "  dispatcher: ${hooks_base}/qemu"
echo "  pre VM:     ${hooks_dst}/prepare/begin/start.sh"
echo "  post VM:    ${hooks_dst}/release/end/revert.sh"
echo "  config:     ${etc_dir}/gpu-handoff.conf"
echo ""
echo "VNC (daily):"
echo "  sudo windows11-mode console"
echo "  windows11-console"
echo ""
echo "Single-GPU passthrough:"
echo "  sudo windows11-dump-vbios"
echo "  sudo windows11-mode passthrough    # creates ${enable_file}"
echo "  windows11-start --yes            # stops Hyprland, detaches GPU, starts VM"
echo "  windows11-stop                   # clean shutdown → revert hook → Hyprland"
echo ""
echo "Emergency: windows11-force-stop && sudo windows11-revert-host"
echo ""
echo "IOMMU (once): sudo vfio-limine-enable --iommu-only && sudo reboot"
