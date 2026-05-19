# CapsLock to Escape

This directory keeps the root-owned files needed to make `CapsLock` behave like `Escape` across both graphical sessions and Linux virtual consoles.

## Files

- `etc/X11/xorg.conf.d/00-keyboard.conf`: persistent XKB defaults for graphical sessions.
- `etc/vconsole.conf`: points the Linux console at the custom keymap.
- `usr/local/share/kbd/keymaps/capsescape.map`: remaps `CapsLock` to `Escape` for TTYs.
- `install-capsescape.sh`: installs the tracked files into `/etc` and `/usr/local/share`.

## Install

From the repo root, run:

```sh
bash system/install-capsescape.sh
```

## Verify

- In Hyprland or another graphical session, press `CapsLock` and confirm it sends `Escape`.
- In a TTY, press `CapsLock` and confirm it sends `Escape`.
- Check the installed files in `/etc/X11/xorg.conf.d/00-keyboard.conf` and `/etc/vconsole.conf`.

## GPU undervolt + fan curve (XFX Merc RX 7900 XTX)

Tracked in `etc/lact/config.yaml`. Uses [LACT](https://github.com/ilya-zlobintsev/LACT) with a stable daily undervolt (~**−75 mV** offset, **3020 MHz** core cap, stock **1250 MHz** VRAM) and a junction-based fan curve (zero RPM below ~48°C, ~2200 RPM cap).

Requires amdgpu overdrive (`etc/modprobe.d/99-amdgpu-overdrive.conf`). Reboot after first installing that file.

```sh
pacman -S --needed lact
sudo cp system/etc/modprobe.d/99-amdgpu-overdrive.conf /etc/modprobe.d/
sudo mkinitcpio -P   # if you use mkinitcpio
sudo bash system/install-lact.sh
```

Verify: `cat /sys/class/drm/card*/device/pp_od_clk_voltage` (RX 7900 is usually `card0`) should show `OD_VDDGFX_OFFSET: -75mV` and SCLK max **3020Mhz**.

Edit offsets/clocks in `system/etc/lact/config.yaml` and re-run the install script. GUI: `lact`.
