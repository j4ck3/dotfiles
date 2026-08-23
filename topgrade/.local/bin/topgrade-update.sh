#!/usr/bin/env bash
# Weekly unattended update: run topgrade and notify via Telegram.
set -uo pipefail

telegram_env="${TELEGRAM_ENV:-${HOME}/.config/topgrade/telegram.env}"
[[ -f "${telegram_env}" ]] && set -a && source "${telegram_env}" && set +a

send_telegram() {
  local message=$1
  [[ -n "${TELEGRAM_BOT_TOKEN:-}" && -n "${TELEGRAM_CHAT_ID:-}" ]] || {
    echo "topgrade-update: telegram not configured (${telegram_env}), skipping notification" >&2
    return 0
  }

  curl -fsS -m 30 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${message}" \
    --data-urlencode "disable_web_page_preview=true" \
    >/dev/null
}

if [[ "${1:-}" == "--test-notification" ]]; then
  send_telegram "Test notification from $(hostname -s) at $(date '+%Y-%m-%d %H:%M:%S')"
  exit $?
fi
log="$(mktemp -t topgrade-update.XXXXXX.log)"
trap 'rm -f "${log}"' EXIT

hostname="$(hostname -s)"
started_at="$(date '+%Y-%m-%d %H:%M:%S')"
start_epoch="$(date +%s)"

set +e
topgrade --yes --cleanup --no-ask-retry 2>&1 | tee "${log}"
exit_code="${PIPESTATUS[0]}"
set -e

duration="$(( $(date +%s) - start_epoch ))"
duration_fmt="$(printf '%dm %02ds' $(( duration / 60 )) $(( duration % 60 )))"

if (( exit_code == 0 )); then
  status="OK"
  headline="System update completed on ${hostname}"
else
  status="FAILED"
  headline="System update failed on ${hostname}"
fi

summary="$(grep -Ei '^(error|warning|failed|fel:|varning:)' "${log}" 2>/dev/null | tail -n 8 || true)"
if [[ -z "${summary}" ]]; then
  summary="$(tail -n 12 "${log}")"
fi
summary="$(printf '%s' "${summary}" | tail -c 2800)"

message="$(cat <<EOF
${headline}

Status: ${status}
Started: ${started_at}
Duration: ${duration_fmt}

${summary}
EOF
)"

if send_telegram "${message}"; then
  :
else
  echo "topgrade-update: failed to send telegram notification" >&2
fi

exit "${exit_code}"
