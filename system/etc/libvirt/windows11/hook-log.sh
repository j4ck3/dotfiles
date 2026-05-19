# Shared logging for windows11 libvirt qemu hooks (sourced, not executed).
WINDOWS11_HOOK_LOG="${WINDOWS11_HOOK_LOG:-/var/log/windows11-passthrough-hook.log}"
WINDOWS11_HOOK_LOG_MAX_LINES="${WINDOWS11_HOOK_LOG_MAX_LINES:-3000}"

hook_log_rotate() {
  local log="${WINDOWS11_HOOK_LOG}" max="${WINDOWS11_HOOK_LOG_MAX_LINES}"
  [[ -f "${log}" ]] || return 0
  local lines
  lines="$(wc -l < "${log}" 2>/dev/null || echo 0)"
  [[ "${lines}" -gt "${max}" ]] || return 0
  tail -n "${max}" "${log}" > "${log}.tmp" && mv -f "${log}.tmp" "${log}"
}

hook_log_begin() {
  local tag="$1"
  shift
  install -d -m 0755 "$(dirname "${WINDOWS11_HOOK_LOG}")" 2>/dev/null || true
  touch "${WINDOWS11_HOOK_LOG}" 2>/dev/null || true
  chmod 0644 "${WINDOWS11_HOOK_LOG}" 2>/dev/null || true
  hook_log_rotate
  {
    echo ""
    echo "======== $(date -Iseconds) ${tag} pid=$$ $* ========"
  } >> "${WINDOWS11_HOOK_LOG}" 2>/dev/null || true
}

hook_log_attach() {
  # Tee stdout/stderr (including bash -x) into the log file.
  exec >> >(tee -a "${WINDOWS11_HOOK_LOG}") 2>&1
}
