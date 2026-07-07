# WirePlumber audio priorities

PipeWire default output order (highest wins when device present):

1. **Sound Blaster Play! 3** (USB `041e:324d`) — priority 2000
2. **AMD RX 7900 HDMI** (LG monitor) — priority 1000
3. **Intel ALC1220** onboard — priority 100

## Install

```sh
cd ~/dotfiles
stow -v -R --adopt -t "$HOME" wireplumber
systemctl --user restart wireplumber pipewire
```

Reload after editing rules:

```sh
stow -v -R -t "$HOME" wireplumber
systemctl --user restart wireplumber
```

## Verify

```sh
wpctl status          # * on Sound Blaster sink when DAC connected
pactl get-default-sink
```

If playback still sticks to HDMI, clear stale saved default in `~/.local/state/wireplumber/default-nodes` (remove `hdmi-stereo` lines) and restart WirePlumber.
