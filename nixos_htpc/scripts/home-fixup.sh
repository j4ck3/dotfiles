#!/usr/bin/env bash
# One-time fixups after copying /home/tv from CachyOS. Run as tv on the NixOS guest.
# Idempotent: safe to re-run after another migrate-home.sh pass.
set -euo pipefail
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export PATH=/run/current-system/sw/bin:$HOME/.local/bin:$PATH

# uv tool venvs point at /usr/bin/python (Arch). Rebuild lnxlink on a uv-managed CPython;
# hyprmod comes from nixpkgs now.
if ! "$HOME/.local/share/uv/tools/lnxlink/bin/python" -c 'import lnxlink' 2>/dev/null; then
  uv tool install --force --python-preference only-managed --python 3.14 lnxlink \
    --with dbus-mediaplayer --with dbus-idle --with pulsectl --with nvsmi --with nvitop --with pillow
fi
if [ -d "$HOME/.local/share/uv/tools/hyprmod" ]; then
  uv tool uninstall hyprmod || true
fi
rm -f "$HOME/.local/bin/hyprmod"

# topgrade: NixOS updates come from system.autoUpgrade; keep topgrade for npm/uv/cargo.
mkdir -p "$HOME/.config/topgrade.d"
rm -f "$HOME/.config/topgrade.d/cachyos.toml"
cat > "$HOME/.config/topgrade.d/nixos.toml" <<'TOML'
[misc]
disable = ["system", "shell", "config_update", "nix", "home_manager"]
ignore_failures = ["hyprpm"]
assume_yes = true
TOML

systemctl --user daemon-reload
systemctl --user enable bt-auto-reconnect.timer topgrade-update.timer >/dev/null 2>&1 || true
echo "home fixups done"
