# Docker on cachyos-jacke

## Netdata (this machine, Netbird only)

Compose: `~/work/c/cachyos-jacke` ([j4ck3/c](https://github.com/j4ck3/c/tree/main/cachyos-jacke))

```bash
cd ~/work/c/cachyos-jacke
docker compose up -d
```

**Private URL (Netbird mesh):** http://cachyos-jacke.netbird.hjacke.com:19999

Requires `netbird status` → Management: Connected, with DNS enabled (do not use `--disable-dns`).

## Dockhand (tower)

TCP listener so Dockhand on tower can manage this host’s Docker over Netbird:

```bash
sudo cp systemd/docker.service.d/listen-tcp.conf /etc/systemd/system/docker.service.d/
sudo systemctl daemon-reload
sudo systemctl restart docker
```

In Dockhand: `tcp://<netbird-ip>:2375` (from `netbird status` on this PC).
