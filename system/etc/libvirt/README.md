# Windows 11 on KVM (CachyOS + Hyprland + RX 7900)

Single-GPU passthrough follows [VFIO-Tools libvirt hooks](https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/) and [joeknock90 Single-GPU-Passthrough](https://github.com/joeknock90/Single-GPU-Passthrough), tailored for this host.

## Install once

```sh
sudo bash ~/dotfiles/system/ensure-windows11-live.sh
```

Points `/etc/libvirt/hooks/qemu` and `/usr/local/bin/windows11*` at `~/dotfiles/system`.
After that, edit the repo — **no reinstall / no stow**.

Live paths:


| Path                                                   | Role                                           |
| ------------------------------------------------------ | ---------------------------------------------- |
| `system/etc/libvirt/hooks/qemu`                        | VFIO-Tools dispatcher (via `/etc` symlink)     |
| `hooks/qemu.d/*/prepare/begin/start.sh`                | **Pre:** stop Hyprland → detach GPU            |
| `hooks/qemu.d/*/started/begin/bridge-ensure.sh`        | **Started:** attach guest tap to br0           |
| `hooks/qemu.d/*/release/end/revert.sh`                 | **Post:** reattach GPU → restore Hyprland      |
| `system/etc/libvirt/windows11/gpu-handoff.conf`        | PCI addresses, user, timings                   |
| `/etc/libvirt/hooks/windows11-gpu-passthrough.enabled` | Created by bootstrap / `windows11-mode`        |


Hook log: `/var/log/windows11-passthrough-hook.log`

## Modes


| Command                           | Use                                              |
| --------------------------------- | ------------------------------------------------ |
| `windows11-console`               | **Daily** — VNC/QXL; host keeps GPU + Hyprland   |
| `sudo windows11-mode console`     | Switch domain to VNC                             |
| `sudo windows11-mode passthrough` | GPU passthrough XML + enable hook file           |
| `sudo windows11-mode passthrough-evdev` | GPU + evdev keyboard/mouse passthrough    |
| `windows11-start --yes`           | Start passthrough (runs **prepare** hook first)  |
| `windows11-stop`                  | Shutdown VM → **release** hook restores Hyprland |
| `windows11-force-stop`            | Kill QEMU if stuck                               |
| `sudo windows11-revert-host`      | Manual **post** hook (emergency)                 |
| `windows11-unstick`               | Kill stuck pre-hook + revert                     |


## Single-GPU passthrough flow

```text
windows11-start
    │
    ▼
prepare/begin/start.sh
    ├─ hyprctl dispatch exit  (Hyprland)
    ├─ systemctl stop display-manager
    ├─ unbind vtconsoles / EFI fb
    ├─ modprobe -r amdgpu       (optional, gpu-handoff.conf)
    └─ virsh nodedev-detach GPU + audio
    │
    ▼
QEMU starts → Windows on RX 7900 monitor
    │
    ▼
windows11-stop  (or Start menu shutdown in Windows)
    │
    ▼
release/end/revert.sh
    ├─ virsh nodedev-reattach audio + GPU
    ├─ modprobe amdgpu
    └─ systemctl start display-manager  → Hyprland login
```

**Monitor** must stay on the **RX 7900** during passthrough. Hyprland uses the same GPU when not passthrough (`AQ_DRM_DEVICES` → `amd-card`).

## First-time passthrough checklist

1. BIOS: Above 4G Decoding, **VT-d** (Intel) or **IOMMU / AMD-Vi** (AMD) **enabled**
2. Kernel: `sudo ~/dotfiles/system/usr/local/bin/vfio-limine-enable --iommu-only` then reboot (must see IOMMU groups > 0)
3. `sudo windows11-dump-vbios`
4. Windows in **console mode** first: AMD driver, Fast Startup off, clean shutdown
5. `sudo windows11-mode passthrough` or `sudo windows11-mode passthrough-evdev`
6. `windows11-start --yes`
7. Recovery: SSH → `windows11-force-stop` then `windows11-revert-host` (auto-sudo)

If `virsh nodedev-detach` says VFIO is not supported: confirm IOMMU groups exist (`find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 | head`), fix cmdline (`sudo ~/dotfiles/system/usr/local/bin/vfio-limine-enable --iommu-only` — uses `amd_iommu=on` on Ryzen, `intel_iommu=on` on Intel), reboot, reinstall hooks, retry.

### Black screen / picture on Intel iGPU only

Your board has **Intel iGPU + RX 7900**. During passthrough the **7900 goes to the VM**. The motherboard HDMI/DP (Intel) will be **black** or show **Linux kernel text** (e.g. `amdgpu: overdrive is enabled` when the host reloads the AMD driver) — that is **not** Windows.

1. Plug the monitor into the **RX 7900** (not ASUS rear HDMI from Intel).
2. Run `windows11-passthrough-doctor` while the VM is running (GPU driver should be `vfio-pci`).
3. First-time Windows: use **console mode** (`windows11-console`) and install the AMD driver via VNC before relying on passthrough output.
4. Re-apply passthrough XML if the 7900 stays black with the cable on the card: `sudo windows11-mode passthrough` (keeps explicit VBIOS, disables ROM BAR).
5. Re-dump VBIOS if still black: `sudo windows11-dump-vbios` (VM off, GPU on host).

## VNC (no passthrough)

```sh
sudo windows11-mode console
windows11-console
```

## VM detection hardening

Passthrough mode applies only the anti-detection XML needed by the current pafish
run:

- hide KVM with `<kvm><hidden state="on"/></kvm>`
- disable the CPUID hypervisor feature bit
- remove Hyper-V enlightenments so Windows does not see `KVM Hv`
- provide SMBIOS sysinfo so Windows does not report a BOCHS BIOS version

It deliberately does **not** change VirtIO storage/network, MAC address, USB
devices, or QEMU itself. Pafish already passed those checks, and changing them
would add driver and boot risk without evidence.

After applying passthrough XML, rerun pafish in Windows and expect these to
change to OK:

- `Checking hypervisor bit in cpuid feature bits`
- `Bochs detection: SystemBiosVersion`
- the CPU header should no longer show `Hypervisor: KVM Hv`

Expected remaining pafish traces:

- `rdtsc forcing VM exit` — timing-level VM behavior, not fixed by safe XML
  changes
- mouse/dialog checks — rerun after real mouse clicks and dialog interaction
- uptime — rerun after the VM has been running longer

## LAN access from other PCs

Use a real Linux bridge, not libvirt `default` NAT, when the Windows VM should be reachable from other machines on the LAN:

```sh
sudo windows11-mode console
sudo windows11-network apply-bridge
windows11-console
```

`windows11-network apply-bridge` creates a NetworkManager bridge named `br0` over the wired default-route interface, then switches the VM NIC to `<interface type="bridge">` with **`managed="no"`** (required when NetworkManager owns `br0`; without it the guest tap never joins the bridge and Windows has no internet). On this host that means `eno1` becomes a slave of `br0`, and both the host and the Windows VM get normal LAN DHCP addresses from the router.

For **windows11-stealth** (Intel `e1000e` NIC, not VirtIO):

```sh
sudo DOMAIN=windows11-stealth windows11-stealth-ensure-network   # VM shut off
```

If the VM is already running with no internet:

```sh
sudo DOMAIN=windows11-stealth windows11-network fix-bridge
```

If Windows was previously pinned to `192.168.122.10`, run `windows11-set-libvirt-ip.ps1` in an elevated PowerShell inside the VM to reset the NIC to DHCP. Stealth uses **e1000e**, not VirtIO — Windows inbox driver should work; use Device Manager only if the adapter shows with a warning icon.

## Tune this machine

Edit `~/dotfiles/system/etc/libvirt/windows11/gpu-handoff.conf` (live — no install):


| Variable           | Default | Meaning                                                  |
| ------------------ | ------- | -------------------------------------------------------- |
| `CONSOLE_USER`     | jacke   | Hyprland user for `hyprctl dispatch exit`                |
| `DETACH_SLEEP`     | 3       | Pause after stopping DM                                  |
| `SKIP_EFI_FB`      | 0       | Set `1` to skip EFI framebuffer unbind (some AMD boards) |
| `UNLOAD_AMGPU`     | 1       | `modprobe -r amdgpu` before detach                       |


## References

- [VFIO-Tools](https://github.com/PassthroughPOST/VFIO-Tools) — `libvirt_hooks/qemu`
- [Single-GPU-Passthrough](https://github.com/joeknock90/Single-GPU-Passthrough) — example start/revert scripts
- [Libvirt hooks](https://www.libvirt.org/hooks.html)

## Files


| Path                            | Purpose                      |
| ------------------------------- | ---------------------------- |
| `windows11-amd-gpu-hostdev.xml` | GPU + HDMI audio + VBIOS ROM |
| `windows11-passthrough-usb.xml` | Optional USB HID passthrough |
| `windows11-passthrough-evdev.xml` | Optional evdev keyboard/mouse passthrough |
| `windows11/gpu-handoff.sh`      | Shared pre/post logic        |
