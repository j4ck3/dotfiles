#!/usr/bin/env bash
# Safe regression tests: every invocation uses --preview; no power actions.
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
script="$root/.config/hypr/scripts/session-action"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin" "$tmp/runtime"

cat > "$tmp/bin/qs" <<'STUB'
#!/usr/bin/env bash
case "${*: -1}" in
  playSessionAnimation)
    case "$SCENARIO" in
      missing) exit 1 ;;
      busy) echo busy ;;
      *) echo started ;;
    esac ;;
  sessionAnimationStatus)
    case "$SCENARIO" in
      interrupted) echo idle ;;
      timeout) echo active ;;
      *) echo complete ;;
    esac ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$tmp/bin/qs"

for action in suspend poweroff reboot logout; do
  output=$(PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/runtime" SCENARIO=success \
    "$script" --preview "$action")
  [[ $output == "Preview complete; skipped: "* ]] || exit 1
done
for scenario in missing busy interrupted timeout; do
  if PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/runtime" SCENARIO="$scenario" \
    "$script" --preview suspend >"$tmp/output" 2>&1; then
    echo "FAIL: $scenario should reject action" >&2
    exit 1
  fi
  ! grep -q 'Preview complete' "$tmp/output"
done
if "$script" --preview invalid >"$tmp/output" 2>&1; then
  echo 'FAIL: invalid action accepted' >&2
  exit 1
fi
(
  flock -n 9
  if PATH="$tmp/bin:$PATH" XDG_RUNTIME_DIR="$tmp/runtime" SCENARIO=success \
    "$script" --preview suspend >"$tmp/output" 2>&1; then
    echo 'FAIL: concurrent action accepted' >&2
    exit 1
  fi
) 9>"$tmp/runtime/quickshell-session-action.lock"
echo 'PASS: four previews; missing/busy/interrupted/timeout/invalid/concurrent rejected'

if [[ ${1:-} == --live ]]; then
  for action in suspend poweroff reboot logout; do
    "$script" --preview "$action" &
    preview_pid=$!
    sleep 0.2
    # Every output's animation must also cover any reserved Quickshell bar.
    hyprctl layers -j | jq -e '
      all(.[];
        .levels as $levels |
        [$levels["3"][] | select(.namespace == "qs-session-animation")] as $overlays |
        ($overlays | length) == 1 and
        all($levels["2"][] | select(.namespace == "quickshell-bar");
          . as $bar | $overlays[0] as $a |
          $a.x <= $bar.x and $a.y <= $bar.y and
          ($a.x + $a.w) >= ($bar.x + $bar.w) and
          ($a.y + $a.h) >= ($bar.y + $bar.h)))
    ' >/dev/null
    wait "$preview_pid"
    sleep 1.1
    [[ $(qs ipc -p "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell" call shell sessionAnimationStatus) == idle ]]
  done
  echo 'PASS: live animations completed and reset; all power commands skipped'
fi
