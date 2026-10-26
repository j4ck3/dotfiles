#!/usr/bin/env bash
# Easy Effects (Flatpak) EQ toggle for the Quickshell Utilities popup.
# Commands:
#   status  -> JSON {"running":bool,"enabled":bool,"preset":"..."}
#   toggle  -> flip global bypass; starts the service (with preset) when not running
#   on|off  -> force enabled / bypassed
# The status path never launches Easy Effects: calling the CLI with no running
# instance would start a full app, so it checks the process first.
set -u
app=com.github.wwmm.easyeffects
starter="$HOME/.config/hypr/scripts/start-easyeffects"

ee() { flatpak run "$app" "$@" 2>/dev/null; }
running() { pgrep -x easyeffects >/dev/null; }

# Global bypass state: 1 = bypassed (EQ off), 2 = active (EQ on).
bypass_state() { ee -b 3 | grep -v '^[[:space:]]*$' | tail -n1 | tr -dc '0-9'; }

status() {
	if ! running; then
		printf '{"running":false,"enabled":false,"preset":""}\n'
		return
	fi
	local b preset
	b=$(bypass_state)
	preset=$(ee -a output | grep -v '^[[:space:]]*$' | tail -n1)
	preset=${preset//\\/\\\\}
	preset=${preset//\"/\\\"}
	if [[ "$b" == "2" ]]; then
		printf '{"running":true,"enabled":true,"preset":"%s"}\n' "$preset"
	else
		printf '{"running":true,"enabled":false,"preset":"%s"}\n' "$preset"
	fi
}

set_enabled() {
	if ! running; then
		[[ "$1" == "on" ]] || return 0
		# Start the service with the preset; bypass is persisted across runs,
		# so clear it explicitly once the service is up.
		"$starter" && ee -b 2 >/dev/null
		return
	fi
	if [[ "$1" == "on" ]]; then ee -b 2 >/dev/null; else ee -b 1 >/dev/null; fi
}

case "${1:-status}" in
status) status ;;
on) set_enabled on ;;
off) set_enabled off ;;
toggle)
	if running && [[ "$(bypass_state)" == "2" ]]; then
		set_enabled off
	else
		set_enabled on
	fi
	;;
*)
	echo "usage: $0 status|toggle|on|off" >&2
	exit 2
	;;
esac
