# GTK/Qt theme (light)

GTK/Qt apps, portals, and Flatpaks use Adwaita light. Helium follows the system theme (no forced browser dark). Dark Reader remains in managed extensions if you want darker pages.

## Install

```sh
cd ~/dotfiles
stow -v -R -t "$HOME" theme
chmod +x theme/.local/bin/*
apply-gnome-theme
apply-flatpak-theme
```

Reload Hyprland config (`hyprctl reload`) or re-login so `envs.conf` vars apply.

## What it sets

| Layer | Mechanism |
| ----- | --------- |
| GTK 3/4 | `~/.config/gtk-*/settings.ini`, `~/.gtkrc-2.0` |
| Hyprland | `hypr/.config/hypr/envs.conf` (`COLOR_SCHEME`, `GTK_THEME`, Qt) |
| systemd user | `~/.config/environment.d/99-theme.conf` |
| GNOME portal | `apply-gnome-theme` (gsettings, autostart) |
| Flatpak | `apply-flatpak-theme` (run once after flatpak install) |

Remove stale dark config if you previously stowed theme:

```sh
rm -f ~/.config/environment.d/99-dark.conf
```
