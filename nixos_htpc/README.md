# nixos_htpc

NixOS configuration for the HTPC VM on the Unraid server `tower`. It replaces
the CachyOS HTPC and keeps the same desktop: Hyprland with the Lua config from
`hypr_htpc`, the Quickshell bar, Helium opening YouTube on workspace 1,
lnxlink for Home Assistant, NetBird, and wayvnc.

The flake only covers the system. The user `tv` keeps the same home directory
as before, so `~/.config/hypr`, `~/.config/quickshell`, the systemd user
units and the Helium profile still come from the stow packages in this repo.

## Layout

| Path | Purpose |
| ---- | ------- |
| `flake.nix` | `nixosConfigurations.nixos-tv`, plus `packages.x86_64-linux.image` (raw EFI disk image) |
| `configuration.nix` | Packages, services, NVIDIA 580 legacy driver, locale, firewall, FHS symlinks for scripts that call `/usr/bin/...` |
| `modules/vm-disk.nix` | q35/OVMF disk layout (labels `nixos` and `ESP`), systemd-boot |
| `secrets.nix.example` | Password hashes. Copy it to `secrets.nix`; git ignores that file |
| `libvirt/NixOS-HTPC.xml` | Unraid domain: GTX 1060 + HDMI audio + two Renesas USB cards passed through, vCPUs pinned to host CPUs 8-19 |
| `scripts/migrate-home.sh` | Copies `/home/tv`, Bluetooth pairings and (with `--with-identity`) NetBird state and SSH host keys from the CachyOS VM into the NixOS disk image |
| `scripts/home-fixup.sh` | Run once as `tv` after a copy: rebuilds the lnxlink uv venv on a uv-managed Python and swaps the topgrade CachyOS profile for a NixOS one |
| `scripts/cutover.sh` | Final sync, shuts down CachyOS and starts NixOS-HTPC. `cutover.sh back` reverses it |
| `scripts/gexec.sh` | Runs a shell command in a libvirt guest through the QEMU guest agent |

## Rebuild on the HTPC

The live system builds from `/etc/nixos`, which is a plain directory, not a git
checkout. Flakes inside a git repository only see tracked files, so building
from this repo would skip the ignored `secrets.nix`.

To change the system, edit the files here, copy them to `/etc/nixos` with
`secrets.nix` alongside them, then run:

```sh
sudo nixos-rebuild switch --flake /etc/nixos#nixos-tv
```

`system.autoUpgrade` runs the same rebuild every Sunday at 05:30 with a fresh
lock file (newer nixpkgs and Helium). topgrade still runs at 06:00 for
npm, uv and cargo.

## pi and Claude

`pi` (pi-coding-agent) and Claude Code come from nixpkgs and update with the
system. Claude models run through the
[pi-claude-bridge](https://github.com/elidickinson/pi-claude-bridge) extension,
which drives the unmodified `claude` binary, so they bill against the Claude
subscription that `claude` is signed in to:

```sh
claude auth login                 # once, through Anthropic's sign-in page
pi install npm:pi-claude-bridge   # already installed on the HTPC
```

`~/.pi/agent/claude-bridge.json` points `pathToClaudeCodeExecutable` at
`/run/current-system/sw/bin/claude`. In pi, pick a `claude-bridge/...` model
with `/model`. The `anthropic/...` models are pi's own provider; don't sign in
to them with a subscription through pi's `/login`.

## Build a fresh disk image

Run this on any x86_64 machine with Nix and KVM. On tower it runs inside the
`nixos/nix` Docker container:

```sh
nix build .#packages.x86_64-linux.image
```

The result is a raw EFI image. Copy it to `/mnt/user/domains/NixOS-HTPC/vdisk1.img`,
grow it with `truncate -s 100G`, then grow partition 2 and the ext4
filesystem before copying the home directory into it.

## Differences from CachyOS

- `linuxPackages_latest` instead of the CachyOS kernel. ananicy-cpp uses the
  CachyOS rule set.
- Helium comes from the `oxcl/nix-flake-helium-browser` flake.
  `helium-browser` is a wrapper that reads `~/.config/helium-browser-flags.conf`
  the way the AUR package did. Spotify has a similar wrapper for
  `spotify-flags.conf`.
- Kept to what the TV uses: Ghostty is the only terminal, mpv the only
  video player, nautilus the file manager. Cursor, T3 Code, OpenCode,
  Docker, Sunshine, Flatpak/Stremio, VLC, Dolphin and the build
  toolchain were dropped on 2026-11-05.
- The NOPASSWD sudo rule covers `nixos-rebuild` and `nix-collect-garbage`
  instead of pacman and yay.
