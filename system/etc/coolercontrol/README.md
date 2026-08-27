# CoolerControl fan curves

Tracked copies of `/etc/coolercontrol/{config.toml,modes.json}`.

**Not tracked:** `.passwd`, TLS certs/keys, `config-ui.json`.

## Live now (TUF GAMING Z790-PLUS WIFI + i9-14900KS + amdgpu)

| Mode | Switch in UI |
|------|----------------|
| **Balanced** (active) | quieter idle, ramps on heat |
| **Performance** | higher floors, snappier response |

### Assignments (heuristic — confirm with fan-identify.sh)

| Channel | Profile | Notes |
|---------|---------|-------|
| `nct6798` fan1, fan2, fan5 | CPU curve | silkscreen mapping unconfirmed |
| `nct6798` fan4, fan7 | Case Mix = max(CPU, GPU) | silkscreen mapping unconfirmed |
| `nct6798` fan3 | RPM-only (no PWM) | likely CPU_OPT tach or secondary sense |
| `nct6798` fan6 | unused (0 RPM) | likely empty header |
| `amdgpu` fan1 | GPU curve | 0% below ~45 °C edge; not a motherboard header |

Board has **7 physical 4-pin headers** (manual): CPU_FAN, CPU_OPT, AIO_PUMP, CHA_FAN1–4. CPU_FAN + CPU_OPT share Q-Fan group **A** (OPT slaved to CPU_FAN PWM). Linux `fan1`–`fan7` ≠ silkscreen names — use identify script + case open.

Wrong header mapping? Reassign in CoolerControl Controls page, then update Mode.

## Quickshell Power menu

`CASE FANS` slider in Power popup → temporary fixed duty on fan4/7 via CoolerControl API.

- Scripts: `hypr/.config/quickshell/scripts/fan-{common,status,control}.sh`
- Token: `~/.config/coolercontrol/token` (Bearer, write access) — not in git
- **Auto** = Case Balanced curve. **Quiet** = fixed 20%. **Max** = fixed 100% on fan4/7.

### Curves (duty %)

**CPU Balanced** @ package temp: 25→25→32→45→60→80→95→100 at 0/40/50/60/70/80/90/100 °C  
**GPU Balanced** @ edge: 0 below 45 °C, then 25→35→50→70→90→100  
**Case** = Mix Max of slightly higher CPU/GPU curves  
**Smooth Quiet** function: hysteresis, slow down-ramp, step limits

## Restore

```sh
sudo systemctl stop coolercontrold
sudo cp ~/dotfiles/system/etc/coolercontrol/config.toml /etc/coolercontrol/
sudo cp ~/dotfiles/system/etc/coolercontrol/modes.json /etc/coolercontrol/
sudo systemctl start coolercontrold
```

Or edit live in CoolerControl UI — daemon writes `/etc/coolercontrol/` itself. Re-copy into this folder when curves change and you want them in git.
