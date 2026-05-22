# CapsLock to Escape

This directory keeps the root-owned files needed to make `CapsLock` behave like `Escape` across both graphical sessions and Linux virtual consoles.

## Files

- `etc/X11/xorg.conf.d/00-keyboard.conf`: persistent XKB defaults for graphical sessions.
- `etc/vconsole.conf`: points the Linux console at the custom keymap.
- `usr/local/share/kbd/keymaps/capsescape.map`: remaps `CapsLock` to `Escape` for TTYs.
- `install-capsescape.sh`: installs the tracked files into `/etc` and `/usr/local/share`.

## Account lockout (`faillock`)

`faillock/etc/security/faillock.conf` — softer defaults than stock (5 tries / 2 min window / 5 min lock).

```sh
cd ~/dotfiles
# stow needs a symlink target; remove the plain file first (or use --adopt)
sudo rm -f /etc/security/faillock.conf
sudo stow -v -R -t / faillock
```

If `/etc/security/faillock.conf` already exists and you want stow to take it over in one step:

```sh
cd ~/dotfiles
sudo stow -v -R --adopt -t / faillock
```

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

## Pre-topgrade backup (Snapper + tower)

CachyOS ships **Snapper** (`cachyos-snapper-support`) and it **conflicts with Timeshift**, so this setup uses Snapper for local BTRFS snapshots. Before `topgrade` runs, a snapshot is created and rsynced to **tower** at `/mnt/disk1/backups/<hostname>/snapshots/`. Incremental transfers use `rsync --link-dest` against the previous remote snapshot.

### Files

- `usr/local/bin/backup-before-topgrade`: snapshot, sync, retention, logging
- `etc/backup/backup.conf`: hostname, SSH target, snapper config, retention
- `install-backup.sh`: installs packages, configs, and the script
- `../backup/.config/topgrade.d/backup.toml`: topgrade `pre_commands` hook (stow `backup`)

### Install

```sh
cd ~/dotfiles
grep -v '^#' packages.txt | grep -E '^(snapper|snap-pac|rsync)$' | xargs -r sudo pacman -S --needed --noconfirm --
stow -v -R -t "$HOME" backup
sudo bash system/install-backup.sh
sudo snapper -c root list
```

Run once manually before unattended `topgrade` (first rsync can take a long time):

```sh
/usr/local/bin/backup-before-topgrade
topgrade
```

Logs: `~/.local/state/backup-before-topgrade.log`

### Config

Edit `/etc/backup/backup.conf` after install (or change defaults in `system/etc/backup/backup.conf` and re-run install):

| Variable | Default | Meaning |
| -------- | ------- | ------- |
| `BACKUP_HOSTNAME` | `cachyos-jacke` | Remote folder name under `/mnt/disk1/backups/` |
| `SSH_TARGET` | `tower` | SSH config host |
| `SNAPPER_CONFIG` | `root` | Snapper config name |
| `KEEP_LOCAL` | `3` | Local pre-topgrade snapshots to keep |
| `KEEP_REMOTE` | `5` | Remote snapshot directories to keep |
| `MIN_FREE_GB` | `10` | Abort if less free on `/` |
| `RSYNC_PROGRESS` | `1` | Show rsync progress bar on a TTY (`0` to disable) |

Only snapshots whose description starts with `pre-topgrade` are pruned locally. Pacman snapshots from `snap-pac` are left alone.

Large paths like `/var/lib/libvirt/images/` are still captured in BTRFS snapshots. Exclude them in snapper if you do not want VM disks in backups.

### Restore

- **Local:** `sudo snapper -c root list`, then `sudo snapper -c root undochange` or restore individual files from `/.snapshots/N/snapshot/`.
- **From tower:** rsync a snapshot back, e.g. `rsync -aHAXx tower:/mnt/disk1/backups/cachyos-jacke/snapshots/DATE-snapN/ /tmp/restore/`, then copy files as needed. Full bare-metal restore is manual; test occasionally.
