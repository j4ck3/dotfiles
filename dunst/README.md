# Dunst notifications

`libnotify` clients (`notify-send`, scripts, Flatpak apps) use Dunst on Hyprland.

Styled like **macOS dark banners**: rounded frosted card, Inter font, top-right stack. Hypr `layerrule` blur on layer namespace `dunst`.

## Install

```sh
sudo pacman -S --needed dunst inter-font
cd ~/dotfiles
stow -v -R -t "$HOME" dunst
```

Hyprland starts Dunst via `start-dunst` (`~/.local/bin`, from this package). Reload config or re-login:

```sh
stow -v -R -t "$HOME" dunst
start-dunst
hyprctl reload
```

If `stow hypr` fails with conflicts, `stow dunst` is enough for Dunst + `start-dunst`.

## Test

```sh
notify-send "Dunst" "Normal urgency"
notify-send -u low "Dunst" "Low urgency"
notify-send -u critical "Dunst" "Critical (stays until dismissed)"
```
