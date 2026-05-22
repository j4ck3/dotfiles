#!/usr/bin/env bash
# Chris Titus Linux benchmark workflow (Phoronix + MangoHud + plot.py)
# https://christitus.com/how-to-benchmark-in-linux/
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
benchmark_repo="${LINUX_BENCHMARKS_REPO:-$HOME/linux-benchmarks}"
log_dir="${BENCHMARK_LOG_DIR:-$HOME/benchmark-logs}"

# CPU workloads from the guide; add more pts/... tests as needed.
DEFAULT_TESTS=(pts/c-ray pts/compress-7zip pts/openssl)

usage() {
  cat <<EOF
Usage: $(basename "$0") <command> [options]

Commands:
  prep              Set performance governor and show system metadata
  run               Run Phoronix batch benchmarks with MangoHud logging
  export <result>   Export a saved Phoronix result set to CSV in ${log_dir}
  plot              Generate PNG charts from ${log_dir}
  full              prep + run + export + plot (run options passed through)

Run options (for 'run' / 'full'):
  --name NAME       TEST_RESULTS_NAME (default: pc-benchmark)
  --id ID           TEST_RESULTS_IDENTIFIER (required for comparisons)
  --desc TEXT       TEST_RESULTS_DESCRIPTION
  --runs N          Repeat each test N times (default: 5)
  --tests T1,T2     Comma-separated test profiles (default: ${DEFAULT_TESTS[*]})

Examples:
  $(basename "$0") prep
  $(basename "$0") run --name baseline --id undervolt-baseline --desc "After undervolt"
  $(basename "$0") export baseline
  $(basename "$0") plot

Install tools first: sudo ${repo}/install-linux-benchmark.sh
One-time: phoronix-test-suite batch-setup
EOF
}

require_phoronix() {
  if ! command -v phoronix-test-suite >/dev/null; then
    echo "phoronix-test-suite not found. Run: sudo ${repo}/install-linux-benchmark.sh" >&2
    exit 1
  fi
}

require_plot_repo() {
  if [[ ! -f "${benchmark_repo}/plot.py" ]]; then
    echo "plot.py not found. Clone: git clone https://github.com/ChrisTitusTech/linux-benchmarks.git ${benchmark_repo}" >&2
    exit 1
  fi
}

cmd_prep() {
  echo "=== System metadata (save with your results) ==="
  date -Is
  uname -r
  command -v phoronix-test-suite >/dev/null && phoronix-test-suite system-info 2>/dev/null | head -40 || true
  if [[ -r /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]]; then
    echo "CPU governor (before): $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    if command -v cpupower >/dev/null; then
      sudo cpupower frequency-set -g performance
      echo "CPU governor (after):  $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
    else
      echo "Install cpupower (linux-tools meta) to switch governor, or set performance in your DE/power profile."
    fi
  fi
  sensors 2>/dev/null | head -25 || true
  echo
  echo "Before benchmarking: reboot, close browsers/Discord/RGB tools, use the same power profile each run."
  mkdir -p "${log_dir}"
}

setup_mangohud_env() {
  export MANGOHUD=1
  export MANGOHUD_CONFIG="output_folder=${log_dir},autostart_log=1,benchmark_percentiles=AVG+1+0.1"
}

cmd_run() {
  require_phoronix
  local name="pc-benchmark" id="" desc="" runs=5
  local -a tests=("${DEFAULT_TESTS[@]}")

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name) name="$2"; shift 2 ;;
      --id) id="$2"; shift 2 ;;
      --desc) desc="$2"; shift 2 ;;
      --runs) runs="$2"; shift 2 ;;
      --tests)
        IFS=',' read -r -a tests <<<"$2"
        shift 2
        ;;
      *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
  done

  if [[ -z "${id}" ]]; then
    echo "--id is required (e.g. --id undervolt-baseline)" >&2
    exit 1
  fi

  [[ -n "${desc}" ]] || desc="Benchmark run ${id} on $(uname -r)"

  mkdir -p "${log_dir}"
  setup_mangohud_env

  echo "=== Phoronix batch benchmark ==="
  echo "  Name:        ${name}"
  echo "  Identifier:  ${id}"
  echo "  Description: ${desc}"
  echo "  Tests:       ${tests[*]}"
  echo "  MangoHud:    ${log_dir}"
  echo

  TEST_RESULTS_NAME="${name}" \
  TEST_RESULTS_IDENTIFIER="${id}" \
  TEST_RESULTS_DESCRIPTION="${desc}" \
  TEST_EXEC_PREPEND="mangohud" \
  phoronix-test-suite batch-benchmark "${tests[@]}"
}

cmd_export() {
  require_phoronix
  local result_name="${1:-}"
  if [[ -z "${result_name}" ]]; then
    echo "Usage: $(basename "$0") export <result-name>" >&2
    echo "List results: phoronix-test-suite list-results" >&2
    exit 1
  fi
  mkdir -p "${log_dir}"
  local out="${log_dir}/${result_name}.csv"
  phoronix-test-suite result-file-to-csv "${result_name}" "${out}"
  echo "Exported: ${out}"
}

cmd_plot() {
  require_plot_repo
  mkdir -p "${log_dir}"
  if ! compgen -G "${log_dir}/*.csv" >/dev/null; then
    echo "No CSV files in ${log_dir}. Run benchmarks and export first." >&2
    exit 1
  fi
  local plot_python=python3
  if [[ -x "${benchmark_repo}/.venv/bin/python" ]]; then
    plot_python="${benchmark_repo}/.venv/bin/python"
  fi
  "${plot_python}" "${benchmark_repo}/plot.py" --log-dir "${log_dir}"
  echo "Charts written to ${log_dir}"
  ls -1 "${log_dir}"/*.png 2>/dev/null || true
}

cmd_full() {
  cmd_prep
  cmd_run "$@"
  local name="pc-benchmark" id=""
  local args=("$@")
  local i=0
  while [[ $i -lt ${#args[@]} ]]; do
    case "${args[$i]}" in
      --name) name="${args[$((i + 1))]}" ;;
      --id) id="${args[$((i + 1))]}" ;;
    esac
    i=$((i + 1))
  done
  [[ -n "${id}" ]] || { echo "full requires --id" >&2; exit 1; }
  cmd_export "${name}"
  cmd_plot
}

main() {
  local cmd="${1:-}"
  shift || true
  case "${cmd}" in
    prep) cmd_prep ;;
    run) cmd_run "$@" ;;
    export) cmd_export "$@" ;;
    plot) cmd_plot ;;
    full) cmd_full "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "Unknown command: ${cmd}" >&2; usage; exit 1 ;;
  esac
}

main "$@"
