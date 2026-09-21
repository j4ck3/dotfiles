# Docker on cachyos-jacke

## Netdata (this machine, Netbird only)

Compose: `~/work/c/cachyos-jacke` ([j4ck3/c](https://github.com/j4ck3/c/tree/main/cachyos-jacke))

```bash
cd ~/work/c/cachyos-jacke
docker compose up -d
```

**Private URL (Netbird mesh):** http://cachyos-jacke.netbird.hjacke.com:19999

Requires `netbird status` → Daemon: Connected (mesh IP assigned).

This desktop client uses `--disable-dns` so management hostname stays on Pi-hole (`10.0.0.25`) instead of Cloudflare. Peer names like `trilium.netbird.hjacke.com` also come from Pi-hole.

### Netbird broken on LAN (`LoginFailed` / `DeadlineExceeded`)

Two separate problems:

1. **DNS:** Cloudflare (and NetBird mesh DNS) for `netbird.hjacke.com` breaks management gRPC. Pi-hole A record must be `10.0.0.25` (no AAAA `::`). This machine: NetworkManager DNS `10.0.0.53` first.
2. **Traefik 2.11+:** default `readTimeout=60s` kills the idle `/management.ManagementService/Job` stream. On tower: `websecure` `readTimeout`/`idleTimeout` = `24h`, plus `serversTransport` `idleConnTimeout=24h` on the netbird services.

Connect:

```bash
netbird up --management-url https://netbird.hjacke.com:443 --disable-dns
# or: netbird-up
```

Optional hosts fallback: `sudo ~/dotfiles/system/install-netbird-hosts.sh`

After fix: `getent ahostsv4 netbird.hjacke.com` = `10.0.0.25`. Tunnel up even if Management line briefly shows `DeadlineExceeded`.

## Dockhand (tower)

TCP listener so Dockhand on tower can manage this host’s Docker over Netbird:

```bash
sudo cp systemd/docker.service.d/listen-tcp.conf /etc/systemd/system/docker.service.d/
sudo systemctl daemon-reload
sudo systemctl restart docker
```

In Dockhand: `tcp://<netbird-ip>:2375` (from `netbird status` on this PC).
