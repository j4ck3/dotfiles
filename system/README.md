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
