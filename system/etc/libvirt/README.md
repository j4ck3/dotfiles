# Windows 11 on KVM (CachyOS + Hyprland + RX 7900)

Single-GPU passthrough follows [VFIO-Tools libvirt hooks](https://passthroughpo.st/simple-per-vm-libvirt-hooks-with-the-vfio-tools-hook-helper/) and [joeknock90 Single-GPU-Passthrough](https://github.com/joeknock90/Single-GPU-Passthrough), tailored for this host.

## Install once

```sh
sudo bash ~/dotfiles/system/install-libvirt-windows11.sh
```

Installs:


| Path                                                   | Role                                           |
| ------------------------------------------------------ | ---------------------------------------------- |
| `/etc/libvirt/hooks/qemu`                              | VFIO-Tools dispatcher                          |
| `hooks/qemu.d/windows11/prepare/begin/start.sh`        | **Pre:** stop Hyprland → detach GPU            |
| `hooks/qemu.d/windows11/release/end/revert.sh`         | **Post:** reattach GPU → start display-manager |
| `/etc/libvirt/windows11/gpu-handoff.conf`              | PCI addresses, user, timings                   |
| `/etc/libvirt/hooks/windows11-gpu-passthrough.enabled` | Created by `windows11-mode passthrough`        |


Hook log: `/var/log/windows11-passthrough-hook.log`

## Modes


| Command                           | Use                                              |
| --------------------------------- | ------------------------------------------------ |
| `windows11-console`               | **Daily** — VNC/QXL; host keeps GPU + Hyprland   |
| `sudo windows11-mode console`     | Switch domain to VNC                             |
| `sudo windows11-mode passthrough` | GPU passthrough XML + enable hook file           |
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
    ├─ virsh nodedev-detach GPU + audio
    └─ start 15 min watchdog
    │
    ▼
QEMU starts → Windows on RX 7900 monitor
    │
    ▼
windows11-stop  (or Start menu shutdown in Windows)
    │
    ▼
release/end/revert.sh
    ├─ cancel watchdog
    ├─ virsh nodedev-reattach audio + GPU
    ├─ modprobe amdgpu
    └─ systemctl start display-manager  → Hyprland login
```

**Monitor** must stay on the **RX 7900** during passthrough. Hyprland uses the same GPU when not passthrough (`AQ_DRM_DEVICES` → `amd-card`).

## First-time passthrough checklist

1. BIOS: Above 4G Decoding, Re-Size BAR, **VT-d** (Intel) or **IOMMU / AMD-Vi** (AMD) **enabled**
2. Kernel: `sudo vfio-limine-enable --iommu-only` then reboot (must see IOMMU groups > 0)
3. `sudo windows11-dump-vbios`
4. Windows in **console mode** first: AMD driver, Fast Startup off, clean shutdown
5. `sudo windows11-mode passthrough`
6. `windows11-start --yes`
7. Recovery: SSH → `windows11-force-stop` then `windows11-revert-host` (auto-sudo)

If `virsh nodedev-detach` says VFIO is not supported: confirm IOMMU groups exist (`find /sys/kernel/iommu_groups -mindepth 1 -maxdepth 1 | head`), fix cmdline (`sudo vfio-limine-enable` — uses `amd_iommu=on` on Ryzen, `intel_iommu=on` on Intel), reboot, reinstall hooks, retry.

### Black screen / picture on Intel iGPU only

Your board has **Intel iGPU + RX 7900**. During passthrough the **7900 goes to the VM**. The motherboard HDMI/DP (Intel) will be **black** or show **Linux kernel text** (e.g. `amdgpu: overdrive is enabled` when the host reloads the AMD driver) — that is **not** Windows.

1. Plug the monitor into the **RX 7900** (not ASUS rear HDMI from Intel).
2. Run `windows11-passthrough-doctor` while the VM is running (GPU driver should be `vfio-pci`).
3. First-time Windows: use **console mode** (`windows11-console`) and install the AMD driver via VNC before relying on passthrough output.
4. Re-dump VBIOS if the 7900 stays black with the cable on the card: `sudo windows11-dump-vbios` (VM off, GPU on host).

## VNC (no passthrough)

```sh
sudo windows11-mode console
windows11-console
```

## LAN access from other PCs

Use a real Linux bridge, not libvirt `default` NAT, when the Windows VM should be reachable from other machines on the LAN:

```sh
sudo windows11-mode console
sudo windows11-network apply-bridge
windows11-console
```

`windows11-network apply-bridge` creates a NetworkManager bridge named `br0` over the wired default-route interface, then switches the VM NIC to `<interface type="bridge">`. On this host that means `eno1` becomes a slave of `br0`, and both the host and the Windows VM get normal LAN DHCP addresses from the router.

If Windows was previously pinned to `192.168.122.10`, run `windows11-set-libvirt-ip.ps1` in an elevated PowerShell inside the VM to reset the VirtIO NIC to DHCP. Then use `ipconfig`, your router leases, or `windows11-network status` to find the Windows LAN IP.

If VNC/console clipboard does not work, attach the script as a virtual CD-ROM from the host:

```sh
sudo windows11-tools-iso attach
```

Inside Windows, open the `WIN11_TOOLS` drive and double-click `reset-network-admin.cmd`.

## Tune this machine

Edit `/etc/libvirt/windows11/gpu-handoff.conf`:


| Variable           | Default | Meaning                                                  |
| ------------------ | ------- | -------------------------------------------------------- |
| `CONSOLE_USER`     | jacke   | Hyprland user for `hyprctl dispatch exit`                |
| `DETACH_SLEEP`     | 3       | Pause after stopping DM                                  |
| `SKIP_EFI_FB`      | 0       | Set `1` to skip EFI framebuffer unbind (some AMD boards) |
| `UNLOAD_AMGPU`     | 1       | `modprobe -r amdgpu` before detach                       |
| `WATCHDOG_SECONDS` | 900     | Auto `windows11-watchdog-revert` if VM left running      |


## References

- [VFIO-Tools](https://github.com/PassthroughPOST/VFIO-Tools) — `libvirt_hooks/qemu`
- [Single-GPU-Passthrough](https://github.com/joeknock90/Single-GPU-Passthrough) — example start/revert scripts
- [Libvirt hooks](https://www.libvirt.org/hooks.html)

## Files


| Path                            | Purpose                      |
| ------------------------------- | ---------------------------- |
| `windows11-amd-gpu-hostdev.xml` | GPU + HDMI audio + VBIOS ROM |
| `windows11-passthrough-usb.xml` | Optional USB HID passthrough |
| `windows11/gpu-handoff.sh`      | Shared pre/post logic        |
