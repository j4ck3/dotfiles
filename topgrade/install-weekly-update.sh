#!/usr/bin/env bash
# Install Sunday 06:00 topgrade update timer + passwordless sudo for package managers.
# Usage: ./install-weekly-update.sh
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
unit_src="${repo}/.config/systemd/user"
unit_dst="${HOME}/.config/systemd/user"
bin_src="${repo}/.local/bin"
bin_dst="${HOME}/.local/bin"
config_dst="${HOME}/.config/topgrade"
sudoers_src="${repo}/etc/sudoers.d/topgrade-unattended"
sudoers_dst="/etc/sudoers.d/topgrade-unattended"

install_sudoers_as_root() {
  if ! visudo -cf "${sudoers_src}" >/dev/null; then
    echo "error: invalid sudoers file: ${sudoers_src}" >&2
    exit 1
  fi
  install -m 0440 "${sudoers_src}" "${sudoers_dst}"
  if ! visudo -cf "${sudoers_dst}" >/dev/null; then
    rm -f "${sudoers_dst}"
    echo "error: refused to install broken sudoers" >&2
    exit 1
  fi
  echo "installed ${sudoers_dst}"
}

enable_units_as_user() {
  mkdir -p "${unit_dst}" "${bin_dst}" "${config_dst}"
  ln -sfn "${bin_src}/topgrade-update.sh" "${bin_dst}/topgrade-update.sh"
  chmod +x "${bin_src}/topgrade-update.sh"
  echo "linked ${bin_dst}/topgrade-update.sh"

  if [[ ! -f "${config_dst}/telegram.env" ]]; then
    cp "${repo}/.config/telegram.env.example" "${config_dst}/telegram.env"
    chmod 600 "${config_dst}/telegram.env"
    echo "created ${config_dst}/telegram.env (fill in TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID)"
  fi

  ln -sfn "${unit_src}/topgrade-update.service" "${unit_dst}/topgrade-update.service"
  ln -sfn "${unit_src}/topgrade-update.timer" "${unit_dst}/topgrade-update.timer"
  echo "linked ${unit_dst}/topgrade-update.{service,timer}"

  systemctl --user daemon-reload
  systemctl --user enable --now topgrade-update.timer
  systemctl --user status topgrade-update.timer --no-pager || true
  echo
  echo "Next run: $(systemctl --user show topgrade-update.timer -p NextElapseUSecRealtime --value)"
  echo "Logs:     journalctl --user -u topgrade-update.service"
}

case "${1:-}" in
  --install-sudoers-only)
    if [[ "${EUID}" -ne 0 ]]; then
      echo "error: --install-sudoers-only must run as root" >&2
      exit 1
    fi
    install_sudoers_as_root
    ;;
  --units-only)
    enable_units_as_user
    ;;
  *)
    echo "Installing sudoers (password prompt)..."
    sudo "$0" --install-sudoers-only
    enable_units_as_user
    ;;
esac
