#!/usr/bin/env bash
# Install windows11 KVM helpers, hooks, and libvirt fragments system-wide.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
etc_dir="/etc/libvirt/windows11"
bin_dir="/usr/local/bin"
hooks_dst="/etc/libvirt/hooks/qemu.d/windows11"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run as root: sudo $0" >&2
  exit 1
fi

install -d -m 0755 "${etc_dir}" /var/lib/libvirt/vbios
if [[ -f /etc/libvirt/vbios/rx7900xtx.rom && ! -f /var/lib/libvirt/vbios/rx7900xtx.rom ]]; then
  install -m 0644 /etc/libvirt/vbios/rx7900xtx.rom /var/lib/libvirt/vbios/
fi
chown libvirt-qemu:libvirt-qemu /var/lib/libvirt/vbios 2>/dev/null || true
install -m 0644 "${repo}/etc/libvirt/windows11-amd-gpu-hostdev.xml" "${etc_dir}/"
install -m 0644 "${repo}/etc/libvirt/windows11-passthrough-usb.xml" "${etc_dir}/"
install -m 0644 "${repo}/etc/libvirt/windows11/hook-log.sh" "${etc_dir}/hook-log.sh"
install -m 0644 "${repo}/etc/libvirt/windows11/evdev.conf" "${etc_dir}/evdev.conf"
install -m 0644 "${repo}/etc/libvirt/windows11/looking-glass.ini" "${etc_dir}/looking-glass.ini"
install -m 0644 "${repo}/etc/libvirt/windows11/looking-glass-shm.ini" "${etc_dir}/looking-glass-shm.ini"
install -m 0644 "${repo}/etc/tmpfiles.d/10-looking-glass.conf" /etc/tmpfiles.d/10-looking-glass.conf
sed -i "s/^f \\/dev\\/shm\\/looking-glass 0660 jacke /f \\/dev\\/shm\\/looking-glass 0660 ${SUDO_USER:-jacke} /" /etc/tmpfiles.d/10-looking-glass.conf 2>/dev/null || true
systemd-tmpfiles --create /etc/tmpfiles.d/10-looking-glass.conf 2>/dev/null || true
install -m 0755 "${repo}/etc/libvirt/windows11/patch-domain.py" "${etc_dir}/patch-domain.py"
install -m 0644 "${repo}/etc/modprobe.d/kvmfr.conf" /etc/modprobe.d/kvmfr.conf
install -m 0644 "${repo}/etc/modules-load.d/kvmfr.conf" /etc/modules-load.d/kvmfr.conf
install -m 0644 "${repo}/etc/udev/rules.d/99-kvmfr.rules" /etc/udev/rules.d/99-kvmfr.rules
udevadm control --reload-rules 2>/dev/null || true

touch /var/log/windows11-passthrough-hook.log
chmod 0644 /var/log/windows11-passthrough-hook.log

install -m 0644 "${repo}/etc/modprobe.d/vfio-windows11.conf" /etc/modprobe.d/vfio-windows11.conf

for cmd in windows11-mode windows11-console windows11-stop windows11-force-stop windows11-revert-host windows11-unstick windows11-start windows11-network windows11-disk windows11-dump-vbios windows11-watchdog-cancel windows11-watchdog-revert windows11-looking-glass windows11-looking-glass-doctor windows11-prepare-looking-glass windows11-setup-kvmfr windows11-build-looking-glass-client; do
  install -m 0755 "${repo}/usr/local/bin/${cmd}" "${bin_dir}/${cmd}"
done

install -d -m 0755 "${hooks_dst}/prepare/begin" "${hooks_dst}/release/end"
install -m 0755 "${repo}/etc/libvirt/hooks/qemu.d/windows11/prepare/begin/start.sh" \
  "${hooks_dst}/prepare/begin/start.sh"
install -m 0755 "${repo}/etc/libvirt/hooks/qemu.d/windows11/release/end/revert.sh" \
  "${hooks_dst}/release/end/revert.sh"

if [[ ! -x /etc/libvirt/hooks/qemu ]]; then
  echo "Install libvirt qemu hook helper from passthroughpo.st to /etc/libvirt/hooks/qemu" >&2
fi

# Looking Glass: libvirt must allow QEMU to open /dev/kvmfr0 (B7 ivshmem_kvmfr).
if [[ -f /etc/libvirt/qemu.conf ]] && ! grep -q '"/dev/kvmfr0"' /etc/libvirt/qemu.conf; then
  python3 - <<'PY'
from pathlib import Path

path = Path("/etc/libvirt/qemu.conf")
text = path.read_text(encoding="utf-8")
if '"/dev/kvmfr0"' in text:
    raise SystemExit(0)
old = """#cgroup_device_acl = [
#    "/dev/null", "/dev/full", "/dev/zero",
#    "/dev/random", "/dev/urandom",
#    "/dev/ptmx", "/dev/userfaultfd"
#]"""
new = """cgroup_device_acl = [
    "/dev/null", "/dev/full", "/dev/zero",
    "/dev/random", "/dev/urandom",
    "/dev/ptmx", "/dev/userfaultfd",
    "/dev/kvmfr0"
]"""
if old not in text:
    raise SystemExit("cgroup_device_acl block not found — add \"/dev/kvmfr0\" manually")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
print("Enabled cgroup_device_acl for /dev/kvmfr0")
PY
  systemctl restart libvirtd.service 2>/dev/null || true
fi

if [[ -d /etc/apparmor.d ]]; then
  install -d -m 0755 /etc/apparmor.d/local/abstractions
  install -m 0644 "${repo}/etc/apparmor.d/local/abstractions/libvirt-qemu" \
    /etc/apparmor.d/local/abstractions/libvirt-qemu
  if systemctl is-active --quiet apparmor 2>/dev/null; then
    systemctl reload apparmor 2>/dev/null || systemctl restart apparmor 2>/dev/null || true
  fi
fi

echo "Installed."
echo "Looking Glass:"
echo "  sudo windows11-setup-kvmfr"
echo "  sudo windows11-build-looking-glass-client   # if paru mirror fails"
echo "  sudo usermod -aG kvm ${SUDO_USER:-$USER}"
echo "Next:"
echo "  sudo windows11-dump-vbios"
echo "  sudo windows11-disk backup && sudo windows11-disk check"
echo "  sudo windows11-mode passthrough"
echo "  Install Looking Glass Host in Windows, then: windows11-start && windows11-looking-glass"
