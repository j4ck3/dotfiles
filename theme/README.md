# Dark mode (system-wide)

GTK/Qt apps, portals, Helium, and Flatpaks prefer dark. Websites use Chromium force-dark + Dark Reader (already in managed extensions).

## Install

```sh
cd ~/dotfiles
stow -v -R -t "$HOME" theme
chmod +x theme/.local/bin/*
apply-gnome-dark
apply-flatpak-dark
```

Reload Hyprland config (`hyprctl reload`) or re-login so `envs.conf` vars apply. Restart Helium fully after flag changes.

## What it sets

| Layer | Mechanism |
| ----- | --------- |
| GTK 3/4 | `~/.config/gtk-*/settings.ini`, `~/.gtkrc-2.0` |
| Hyprland | `hypr/.config/hypr/envs.conf` (`COLOR_SCHEME`, `GTK_THEME`, Qt) |
| systemd user | `~/.config/environment.d/99-dark.conf` |
| GNOME portal | `apply-gnome-dark` (gsettings, autostart) |
| Helium | `helium-browser-flags.conf` (`--force-dark-mode`, `WebContentsForceDark`) |
| Flatpak | `apply-flatpak-dark` (run once after flatpak install) |
| Spotify | `spotify-flags.conf` (`--force-dark-mode`) |

Helium also ships Dark Reader via `system/etc/chromium/policies` / `system/usr/share/chromium/extensions`. If pages look double-dark, disable Dark Reader or remove `WebContentsForceDark` from flags.
