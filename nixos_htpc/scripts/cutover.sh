#!/bin/bash
# Swap the HTPC from CachyOS to NixOS-HTPC. Run on tower as root.
#   cutover.sh        # do it
#   cutover.sh back   # roll back to CachyOS
set -euo pipefail
W=$(cd "$(dirname "$0")" && pwd)
img=/mnt/user/domains/NixOS-HTPC/vdisk1.img
wait_off() { for _ in $(seq 1 120); do virsh domstate "$1" | grep -q 'shut off' && return 0; sleep 1; done; virsh destroy "$1"; }

if [[ "${1:-}" == back ]]; then
  virsh shutdown NixOS-HTPC || true; wait_off NixOS-HTPC
  virsh autostart --disable NixOS-HTPC; virsh autostart CachyOS
  virsh start CachyOS
  exit 0
fi

# The test domain boots the same vdisk1.img; remove it so the two can never run together.
if virsh dominfo NixOS-HTPC-test >/dev/null 2>&1; then
  virsh shutdown NixOS-HTPC-test 2>/dev/null || true; wait_off NixOS-HTPC-test || true
  virsh undefine NixOS-HTPC-test --nvram
fi
# Final home sync needs CachyOS running (rsync over ssh + guest agent).
"$W/migrate-home.sh" "$img" --with-identity
virsh shutdown CachyOS; wait_off CachyOS
virsh autostart --disable CachyOS
virsh autostart NixOS-HTPC
virsh start NixOS-HTPC
echo "NixOS-HTPC started; run /etc/nixos/home-fixup.sh as tv once it is up."
