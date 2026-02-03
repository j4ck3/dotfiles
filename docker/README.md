# Docker TCP listener for Dockhand (Tailscale)

Makes the Docker daemon listen on TCP port 2375 so you can add this host in Dockhand on your homeserver over Tailscale.

## Install

```bash
sudo cp systemd/docker.service.d/listen-tcp.conf /etc/systemd/system/docker.service.d/
sudo systemctl daemon-reload
sudo systemctl restart docker
```

## Use in Dockhand

1. On this machine, get your Tailscale IP: `tailscale ip -4`
2. In Dockhand on your homeserver, add a new Docker host with URL: `tcp://<tailscale-ip>:2375`

## Optional: restrict to Tailscale only (UFW)

```bash
sudo ufw allow from 100.64.0.0/10 to any port 2375
sudo ufw reload
```
