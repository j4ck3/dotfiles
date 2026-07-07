# Ly display manager background

Animated login background using Ly’s official [blackhole-smooth](https://codeberg.org/attachments/f336d6ac-8331-4323-91fc-0e4619803401) `.dur` animation (durdraw format).

## Install

```sh
cd ~/dotfiles
sudo bash ly/install-ly-background.sh
```

This copies `ly/etc/ly/backgrounds/blackhole-smooth.dur` to `/etc/ly/backgrounds/` and sets in `/etc/ly/config.ini`:

- `animation = dur_file`
- `dur_file_path = /etc/ly/backgrounds/blackhole-smooth.dur`
- `dur_offset_alignment = center`

## Console font (“zoom out”)

Ly has no zoom setting. It inherits the Linux TTY font (character cell size).

**Common pitfall:** two `FONT=` lines in `/etc/vconsole.conf` — only the **last** wins. Example that blocks zoom-out:

```ini
FONT=default8x9
FONT=ter-v14n   # this one applies; larger than default8x9
```

**Reliable fix:** set font in the Ly systemd unit (Ly resets the TTY on start):

```sh
sudo bash ly/install-ly-font.sh default8x9
# or slightly larger: sudo bash ly/install-ly-font.sh ter-v14n
```

Preview fonts on a raw TTY (`Ctrl+Alt+F3`): `sudo setfont ter-v14n`

## Apply without reinstalling

Ly only reads `/etc/ly/config.ini` when `ly-dm` starts. Logout does **not** reload it.

After editing `config.ini` manually:

```sh
sudo systemctl restart 'ly@tty1.service' 'ly@tty2.service'
# or every ly instance:
sudo systemctl list-units 'ly@*' --no-legend | awk '{print $1}' | xargs -r sudo systemctl restart
```

Check for load errors:

```sh
rg 'dur_file' /var/log/ly.log
```

## Where to browse `.dur` files

| Source | What you get |
|--------|----------------|
| [cmang/durdraw/examples](https://github.com/cmang/durdraw/tree/master/examples) | Official samples (small canvases, good for testing) |
| [cmang/durdraw/discussions](https://github.com/cmang/durdraw/discussions) | Community art posts |
| [Durdraw Discord](https://discord.gg/9TrCsUrtZD) | Shared animations |
| [Ly demo attachment](https://codeberg.org/attachments/f336d6ac-8331-4323-91fc-0e4619803401) | `blackhole-smooth` (240×67) — already in this repo |
| [16colo.rs](https://16colo.rs/) + **durview** | ANSI packs (view with durdraw; not all are `.dur`) |

Preview before installing:

```sh
git clone https://github.com/cmang/durdraw.git /tmp/durdraw
/tmp/durdraw/start-durdraw -p /tmp/durdraw/examples/*.dur
# or one file:
durdraw -p ~/path/to/file.dur
```

Install a pick into Ly:

```sh
sudo install -m644 ~/path/to/file.dur /etc/ly/backgrounds/my-bg.dur
sudo sed -i 's|^dur_file_path = .*|dur_file_path = /etc/ly/backgrounds/my-bg.dur|' /etc/ly/config.ini
sudo systemctl restart 'ly@tty1.service' 'ly@tty2.service'
```

## Ultrawide / full-screen

Ly draws `.dur` at **native size** (columns × lines). It does **not** scale to fill the monitor.

Check your login TTY size (character cells):

```sh
bash ly/scripts/ly-tty-size.sh
# or: rg 'screen resolution' /var/log/ly.log | tail -1
```

On the 21:9 desktop, Ly currently reports `430x160`. The `.dur` must be built at exactly `430x160` or Ly will center it with empty bars.

**Font and `.dur` are coupled:** smaller console font = more rows/cols. After changing font (`install-ly-font.sh`), rebuild the background:

```sh
bash ly/rebuild-fractal-background.sh
sudo bash ly/install-ly-background.sh fractal-ascii.dur
```

Verify the installed file matches the TTY:

```sh
bash ly/scripts/ly-tty-size.sh
python3 - <<'PY'
import gzip, json
with gzip.open('/etc/ly/backgrounds/fractal-ascii.dur', 'rt') as f:
    d = json.load(f)
contents = d['DurMovie']['frames'][0]['contents']
print(f"{max(len(line) for line in contents)}x{len(contents)}")
PY
```

**Fill the whole screen without matching art:**

1. **Built-in Ly animations** — always use the full terminal: set `animation = colormix` (or `matrix`, `doom`, `gameoflife`) and drop `dur_file`.
2. **Wider `.dur`** — create or convert art at your Ly resolution with [durdraw](https://github.com/cmang/durdraw):
   ```sh
   ./start-durdraw -m          # max terminal size
   # or explicit canvas matching ly.log, e.g. ultrawide:
   ./start-durdraw -W 430 -H 160
   ```
   Save as `.dur`, copy to `/etc/ly/backgrounds/`, set `dur_file_path`, restart `ly@*.service`.
3. **Alignment** — `dur_offset_alignment = topleft` + `dur_x_offset` / `dur_y_offset` only moves the patch; it does not stretch it.

For edge-to-edge motion on 3440×1440 without authoring art, `colormix` or `matrix` is usually the easiest option.

## Video → `.dur` (ASCII fractal style)

Default source: Shutterstock-style [ASCII fractal preview](https://www.shutterstock.com/shutterstock/videos/3446957693) (`ly/assets/fractal-ascii-preview.webm`).

Script `ly/scripts/video-to-dur.py`: **cream `█`** where the video is bright, **black** elsewhere — motion stays visible. Default **30 s** loop (`--loop-sec`), **30 fps** capture.

```sh
# Needs: ffmpeg python-pillow
python3 ~/dotfiles/ly/scripts/video-to-dur.py \
  --width 430 --height 160 --style solid --capture-fps 30 --loop-sec 30 \
  --blur 1.2 --temporal 0.28 --luma-threshold 85
# 10s clip @ 30 fps capture → 300 frames → ~10 fps playback → ~30s loop

sudo bash ~/dotfiles/ly/install-ly-background.sh fractal-ascii.dur
```

Other styles: `--style halfblock` (▀), `--style ascii` (img2txt / libcaca).

## Other animations

Ly also ships built-ins (`matrix`, `doom`, `colormix`, `gameoflife`) — set `animation` in `/etc/ly/config.ini` without a `.dur` file.
