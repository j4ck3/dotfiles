#!/usr/bin/env bash
# Install tools for the Chris Titus Linux benchmark workflow:
# https://christitus.com/how-to-benchmark-in-linux/
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
benchmark_repo="${LINUX_BENCHMARKS_REPO:-$HOME/linux-benchmarks}"
log_dir="${BENCHMARK_LOG_DIR:-$HOME/benchmark-logs}"

need_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Run as root: sudo $0" >&2
    exit 1
  fi
}

install_pacman_packages() {
  need_root
  pacman -S --needed --noconfirm mangohud python-pandas git
}

install_phoronix() {
  if command -v phoronix-test-suite >/dev/null; then
    echo "phoronix-test-suite already installed: $(phoronix-test-suite --version)"
    return 0
  fi
  if ! command -v paru >/dev/null && ! command -v yay >/dev/null; then
    echo "Install paru or yay, then: paru -S phoronix-test-suite" >&2
    exit 1
  fi
  local aur_helper=paru
  command -v paru >/dev/null || aur_helper=yay
  echo "Installing phoronix-test-suite from AUR via ${aur_helper}..."
  "${aur_helper}" -S --needed --noconfirm phoronix-test-suite
}

clone_plot_repo() {
  if [[ -d "${benchmark_repo}/.git" ]]; then
    echo "linux-benchmarks repo present at ${benchmark_repo}"
  else
    git clone https://github.com/ChrisTitusTech/linux-benchmarks.git "${benchmark_repo}"
  fi
  if [[ ! -x "${benchmark_repo}/.venv/bin/python" ]]; then
    python3 -m venv "${benchmark_repo}/.venv"
    "${benchmark_repo}/.venv/bin/pip" install -q -r "${benchmark_repo}/requirements.txt"
  fi
}

setup_dirs() {
  mkdir -p "${log_dir}"
  echo "Benchmark logs: ${log_dir}"
}

main() {
  if [[ "${EUID}" -eq 0 ]]; then
    install_pacman_packages
  else
    echo "Skipping pacman (not root). Run: sudo $0"
    pacman -Q mangohud python-pandas &>/dev/null || echo "  Need: sudo pacman -S mangohud python-pandas"
  fi
  install_phoronix
  clone_plot_repo
  setup_dirs
  echo
  echo "Next steps:"
  echo "  1. Reboot, close extra apps, then: ${repo}/linux-benchmark.sh prep"
  echo "  2. One-time: phoronix-test-suite batch-setup"
  echo "  3. Baseline:  ${repo}/linux-benchmark.sh run --name baseline --id undervolt-baseline"
  echo "  4. Charts:    ${repo}/linux-benchmark.sh plot"
}

main "$@"
