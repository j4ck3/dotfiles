# Windows 11 on KVM

## Install once

```sh
sudo bash ~/dotfiles/system/install-libvirt-windows11.sh
```

## Modes

| Command | Use |
|---------|-----|
| `windows11-console` | Daily desktop VM (QXL/VNC), host keeps GPU + keyboard |
| `sudo windows11-mode passthrough` | GPU + Looking Glass + evdev (host keeps USB) |
| `windows11-looking-glass` | View Windows on the Linux desktop (after VM is running) |
| `sudo windows11-mode passthrough-usb` | Legacy: GPU + USB HID to VM (no Looking Glass) |
| `windows11-stop` | Force off VM (uses `windows11-force-stop` if virsh hangs) |
| `windows11-force-stop` | Kill QEMU directly — use when SSH `windows11-stop` hangs |
| `windows11-revert-host` | Reattach GPU + restart display manager after bad shutdown |
| `windows11-unstick` | Kill stuck passthrough hook + reattach GPU (black screen, VM never started) |
| `sudo windows11-disk check` | Repair qcow2 (needs root — file owned by libvirt-qemu) |
| `sudo windows11-dump-vbios` | Dump GPU ROM for VFIO |

## Passthrough checklist (fixes black screen)

1. **BIOS:** Above 4G Decoding **On**, Re-Size BAR **On**, VT-d **On**
2. **Cable:** Monitor on **AMD RX 7900**, not Intel motherboard video
3. **VBIOS:** `sudo windows11-dump-vbios` (VM off, GPU on amdgpu)
4. **Disk:** `sudo windows11-disk backup` then `sudo windows11-disk check`
5. **Windows (console mode first):** AMD driver installed, Fast Startup **off**, clean shutdown
6. **Start:** `windows11-start` (not bare `virsh start`) — includes auto-stop timer
7. **Recovery (read this):** see below — **Ctrl+Alt+F3 does not work** with one monitor on the AMD GPU

## Why Ctrl+Alt+F3 does nothing

Your only monitor is on the **RX 7900**. In passthrough that GPU belongs to Windows, so Linux has **no visible console** on that display. The key combo may switch TTYs, but you cannot see them.

**Use one of these before every passthrough start:**

| Method | How |
|--------|-----|
| **SSH (recommended)** | From phone/laptop: `ssh jacke@YOUR_HOST_IP windows11-force-stop` |
| **Auto-stop timer** | Default 15 min via `windows11-start`; cancel: `ssh … windows11-watchdog-cancel` |
| **Second monitor** | HDMI to **Intel** motherboard port → host TTY visible on that screen |
| **Windows visible** | Shut down from **Start menu** in Windows (runs revert hook) |

**Never hard power-off** — it skips the revert hook and can corrupt the disk.

**Emergency reboot (last resort):** hold power button, or if SysRq enabled: Alt+SysRq, release, type `REISUB` slowly.

## Start passthrough safely

```sh
windows11-start          # prompts, 15 min auto-stop
# or: WINDOWS11_WATCHDOG_SECONDS=600 windows11-start
```

## Passthrough hook log

Start/stop hooks append to:

```text
/var/log/windows11-passthrough-hook.log
```

After a failed start:

```sh
sudo tail -80 /var/log/windows11-passthrough-hook.log
sudo tail -30 /var/log/libvirt/qemu/windows11.log
```

## QEMU log errors explained

- `vfio_container_dma_map ... Invalid argument` → enable **Above 4G Decoding** + **Re-Size BAR** in BIOS (RX 7900 has a 32 GiB BAR); dump VBIOS; confirm `windows11-mode status` shows **GPU VBIOS: yes**
- `windows11-stop` hangs over SSH → use **`windows11-force-stop`** (kills QEMU if virsh blocks)
- VBIOS never sticks in XML → `<rom>` must be under **`<hostdev>`**, not inside `<driver>`; then **`sudo windows11-mode passthrough`**
- `Repairing cluster` on qcow2 → run `sudo windows11-disk check` after unclean shutdown

## Looking Glass + evdev (recommended passthrough)

**Host (once):**

```sh
sudo bash ~/dotfiles/system/install-libvirt-windows11.sh
sudo windows11-setup-kvmfr
sudo windows11-build-looking-glass-client   # if paru/pacman mirror .sig 404
# Or: paru -S looking-glass --needed
sudo usermod -aG kvm "$USER"    # re-login after
# Edit keyboard/mouse paths if needed:
#   /etc/libvirt/windows11/evdev.conf
sudo windows11-mode passthrough
```

If libvirt refuses to start the VM with `/dev/kvmfr0`, edit `/etc/libvirt/qemu.conf`: uncomment `cgroup_device_acl` and add `"/dev/kvmfr0"`, then `sudo systemctl restart libvirtd`.

**Guest (Windows, in console mode first):**

1. Download **Looking Glass Host** from [looking-glass.io](https://looking-glass.io/docs/stable/install_guest/).
2. Install the host application; reboot Windows.
3. Audio comes from the **passed-through GPU HDMI/DP** (virtual `ich9` sound is removed in passthrough mode).

**Daily use:**

```sh
windows11-start --yes
windows11-looking-glass    # fullscreen guest on host monitor
```

Toggle keyboard/mouse: press **both Ctrl keys** (host ↔ guest).

## Networking

User-mode NAT (`10.0.2.15`) is applied by `windows11-mode` / `windows11-network`. Guest tools: `virtio-win-guest-tools.exe`.

## Files

| Path | Purpose |
|------|---------|
| `windows11-amd-gpu-hostdev.xml` | GPU + audio PCI passthrough + ROM |
| `windows11-passthrough-usb.xml` | Optional Razer USB |
| `hooks/qemu.d/windows11/` | Stop Hyprland gracefully, detach GPU |
