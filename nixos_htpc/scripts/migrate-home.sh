#!/bin/bash
# Copy /home/tv and selected root-owned state from the CachyOS HTPC into a
# loop-mounted NixOS-HTPC disk image. Run on tower as root.
#   migrate-home.sh /path/to/vdisk1.img [--with-identity]
# --with-identity also copies NetBird peer state (only at cutover: two peers
# with the same key would fight over the connection).
set -euo pipefail
img=$1; identity=${2:-}
src=tv@10.0.0.164
gexec=${GEXEC:-$(dirname "$0")/gexec.sh}
mnt=$(mktemp -d /tmp/nixhtpc.XXXX)
loop=$(losetup -fP --show "$img")
trap 'sync; umount "$mnt" 2>/dev/null || true; losetup -d "$loop"; rmdir "$mnt"' EXIT
mount "${loop}p2" "$mnt"
mkdir -p "$mnt/home/tv"

rsync -aHAX --numeric-ids --delete --info=progress2 \
  -e "ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o LogLevel=ERROR" \
  --exclude='/.cache/' --exclude='/.npm/_cacache/' \
  --exclude='/.config/Cursor/Cache/' --exclude='/.config/Cursor/CachedData/' \
  --exclude='/.config/net.imput.helium/Singleton*' \
  --exclude='/.local/share/Trash/' \
  --exclude='/.local/share/uv/tools/' --exclude='/.local/share/uv/python/' \
  --exclude='/.local/bin/lnxlink' --exclude='/.local/bin/hyprmod' --exclude='/.local/bin/t3code' \
  --exclude='/.config/topgrade.d/' \
  "$src:/home/tv/" "$mnt/home/tv/"
chown 1000:1000 "$mnt/home/tv"; chmod 700 "$mnt/home/tv"

# Bluetooth pairings (USB BT dongle is passed through, so the adapter MAC matches).
mkdir -p "$mnt/var/lib/bluetooth"
$gexec CachyOS 'tar -C /var/lib/bluetooth -czf - . | base64 -w0' | base64 -d | tar -C "$mnt/var/lib/bluetooth" -xzf -
chmod 700 "$mnt/var/lib/bluetooth"

if [[ "$identity" == --with-identity ]]; then
  rm -rf "$mnt/var/lib/netbird"; mkdir -p "$mnt/var/lib/netbird"
  $gexec CachyOS 'tar -C /var/lib/netbird -czf - . | base64 -w0' | base64 -d | tar -C "$mnt/var/lib/netbird" -xzf -
  # NixOS runs the client with NB_CONFIG=/var/lib/netbird/config.json; CachyOS used the default profile file.
  cp -a "$mnt/var/lib/netbird/default.json" "$mnt/var/lib/netbird/config.json"
  chmod 700 "$mnt/var/lib/netbird"
  # Keep the SSH host keys so clients do not see a changed host.
  mkdir -p "$mnt/etc/ssh"
  $gexec CachyOS 'tar -C /etc/ssh -czf - ssh_host_ed25519_key ssh_host_ed25519_key.pub ssh_host_rsa_key ssh_host_rsa_key.pub | base64 -w0' | base64 -d | tar -C "$mnt/etc/ssh" -xzf -
fi
echo "migrated into $img"
