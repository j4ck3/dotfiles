#!/usr/bin/env bash
# Install pre-topgrade backup: Snapper (BTRFS) + rsync to tower.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
  fi
}

install_packages() {
  need_root
  if pacman -Q cachyos-snapper-support &>/dev/null; then
    echo "Using cachyos-snapper-support (conflicts with timeshift; Snapper is the CachyOS default)."
    pacman -S --needed --noconfirm snapper snap-pac rsync openssh
  else
    pacman -S --needed --noconfirm snapper snap-pac rsync openssh
  fi
}

ensure_snapper_config() {
  need_root
  if [[ ! -f "/etc/snapper/configs/root" ]]; then
    echo "Creating snapper config 'root'..." >&2
    if [[ -f /etc/snapper/config-templates/cachyos-root ]]; then
      cp /etc/snapper/config-templates/cachyos-root /etc/snapper/configs/root
    else
      snapper create-config /
    fi
  fi
}

install_backup_config() {
  need_root
  install -d -m 0755 /etc/backup
  install -m 0644 "${repo}/etc/backup/backup.conf" /etc/backup/backup.conf
}

install_script() {
  need_root
  install -d -m 0755 /usr/local/bin
  install -m 0755 "${repo}/usr/local/bin/backup-before-topgrade" /usr/local/bin/backup-before-topgrade
}

main() {
  need_root
  install_script
  install_backup_config
  install_packages
  ensure_snapper_config

  echo
  echo "Next steps:"
  echo "  cd ~/dotfiles && stow -v -R -t \"\$HOME\" backup"
  echo "  sudo snapper -c root list"
  echo "  /usr/local/bin/backup-before-topgrade"
  echo "  topgrade"
}

main "$@"
