#!/usr/bin/env bash
# Shared 16:9 group geometry and hyprctl dispatches.

MODE_FLAG="${XDG_CONFIG_HOME:-$HOME/.config}/hypr/.16-9-ws-mode"
TERMINAL_16_9_RULE_NAME="terminal-16-9-launch"
# xdg-terminal-exec on this system → Ghostty; keep common emulators for overrides.
TERMINAL_CLASS_RE='com\.mitchellh\.ghostty|ghostty|kitty|Alacritty|foot|org\.wezfurlong\.wezterm'

sixteen_nine_geometry() {
	local mon_id="$1"
	local mon_json
	mon_json=$(hyprctl monitors -j 2>/dev/null | jq -c --argjson id "$mon_id" '.[] | select(.id == $id)')
	[[ -z "$mon_json" ]] && return 1

	local mon_x mon_y mon_w mon_h top bottom
	mon_x=$(jq -r '.x' <<<"$mon_json")
	mon_y=$(jq -r '.y' <<<"$mon_json")
	mon_w=$(jq -r '.width' <<<"$mon_json")
	mon_h=$(jq -r '.height' <<<"$mon_json")
	top=$(jq -r '.reserved[1]' <<<"$mon_json")
	bottom=$(jq -r '.reserved[3]' <<<"$mon_json")

	local gaps_str gaps_l gaps_t gaps_r gaps_b
	gaps_str=$(hyprctl -j getoption general:gaps_out 2>/dev/null | jq -r '.custom')
	gaps_l=0
	gaps_t=0
	gaps_r=0
	gaps_b=0
	[[ -n "$gaps_str" ]] && read -r gaps_l gaps_t gaps_r gaps_b <<<"$gaps_str"

	local work_left work_top work_w work_h
	work_left=$((mon_x + gaps_l))
	work_top=$((mon_y + top + gaps_t))
	work_w=$((mon_w - gaps_l - gaps_r))
	work_h=$((mon_h - top - bottom - gaps_t - gaps_b))

	SIXTEEN_NINE_H=$work_h
	SIXTEEN_NINE_W=$((work_h * 16 * 108 / 9 / 100))
	SIXTEEN_NINE_LEFT=$((work_left + (work_w - SIXTEEN_NINE_W) / 2))
	SIXTEEN_NINE_TOP=$work_top
	# Hyprland windowrule move/size use monitor-local coordinates.
	SIXTEEN_NINE_MOVE_X=$((gaps_l + (work_w - SIXTEEN_NINE_W) / 2))
	SIXTEEN_NINE_MOVE_Y=$((top + gaps_t))
}

sixteen_nine_ensure_terminal_open_rule() {
	local rule="$TERMINAL_16_9_RULE_NAME"
	hyprctl keyword "windowrule[${rule}]:match:class ^(${TERMINAL_CLASS_RE})\$" >/dev/null 2>&1 || true
	hyprctl keyword "windowrule[${rule}]:float on" >/dev/null 2>&1 || true
	hyprctl keyword "windowrule[${rule}]:no_anim on" >/dev/null 2>&1 || true
	hyprctl keyword "windowrule[${rule}]:group set" >/dev/null 2>&1 || true
}

sixteen_nine_activate_terminal_open_rule() {
	local mon_id="$1"
	sixteen_nine_ensure_terminal_open_rule
	sixteen_nine_geometry "$mon_id" || return 1
	local rule="$TERMINAL_16_9_RULE_NAME"
	hyprctl keyword "windowrule[${rule}]:size ${SIXTEEN_NINE_W} ${SIXTEEN_NINE_H}" >/dev/null 2>&1 || true
	hyprctl keyword "windowrule[${rule}]:move ${SIXTEEN_NINE_MOVE_X} ${SIXTEEN_NINE_MOVE_Y}" >/dev/null 2>&1 || true
	hyprctl keyword "windowrule[${rule}]:enable true" >/dev/null 2>&1 || true
}

sixteen_nine_deactivate_terminal_open_rule() {
	hyprctl keyword "windowrule[${TERMINAL_16_9_RULE_NAME}]:enable false" >/dev/null 2>&1 || true
}

sixteen_nine_float_resize() {
	local addr="$1"
	hyprctl --batch \
		"dispatch setfloating address:${addr} ; dispatch resizewindowpixel exact ${SIXTEEN_NINE_W} ${SIXTEEN_NINE_H},address:${addr} ; dispatch movewindowpixel exact ${SIXTEEN_NINE_LEFT} ${SIXTEEN_NINE_TOP},address:${addr}"
}

sixteen_nine_enable_workspace() {
	local ws_id="$1"
	local mode
	mode=$(head -1 "$MODE_FLAG" 2>/dev/null)
	[[ "$mode" == "all" || "$mode" == "$ws_id" ]] || echo "$ws_id" >"$MODE_FLAG"
}

sixteen_nine_apply_to_address() {
	local addr="$1"

	local win_json
	for _ in $(seq 40); do
		win_json=$(hyprctl clients -j 2>/dev/null | jq -c --arg a "$addr" '.[] | select(.address == $a)')
		[[ -n "$win_json" ]] && break
		sleep 0.025
	done
	[[ -z "$win_json" ]] && return 1

	local is_float ws_id mon_id grouped_len
	is_float=$(jq -r '.floating' <<<"$win_json")
	ws_id=$(jq -r '.workspace.id' <<<"$win_json")
	mon_id=$(jq -r '.monitor' <<<"$win_json")
	grouped_len=$(jq -r '.grouped | length' <<<"$win_json")

	# Workspace 2: monocle only unless 16:9 was toggled manually.
	if [[ "$ws_id" == "2" ]]; then
		local mode
		mode=$(head -1 "$MODE_FLAG" 2>/dev/null)
		[[ "$mode" == "all" || "$mode" == "2" ]] || return 0
	fi

	sixteen_nine_enable_workspace "$ws_id"
	sixteen_nine_geometry "$mon_id" || return 1

	# Opened via terminal windowrule: already floating, sized, and grouped.
	if [[ "$is_float" == "true" && "$grouped_len" -gt 0 ]]; then
		return 0
	fi

	local group_addr
	group_addr=$(hyprctl clients -j 2>/dev/null \
		| jq -r --argjson ws "$ws_id" '[.[] | select(.workspace.id == $ws and (.grouped | length) > 0)] | .[0].address // empty')

	# Hide layout changes from the user (tiled → group → float).
	local hide="dispatch setprop address:${addr} opacity 0 override"
	local show="dispatch setprop address:${addr} opacity 1 override"

	if [[ -z "$group_addr" ]]; then
		hyprctl --batch \
			"${hide} ; dispatch settiled address:${addr} ; dispatch focuswindow address:${addr} ; dispatch togglegroup ; dispatch setfloating address:${addr} ; dispatch resizewindowpixel exact ${SIXTEEN_NINE_W} ${SIXTEEN_NINE_H},address:${addr} ; dispatch movewindowpixel exact ${SIXTEEN_NINE_LEFT} ${SIXTEEN_NINE_TOP},address:${addr} ; ${show}"
	else
		hyprctl --batch \
			"${hide} ; dispatch settiled address:${group_addr} ; dispatch focuswindow address:${addr} ; dispatch moveintogroup l ; dispatch moveintogroup r ; dispatch moveintogroup u ; dispatch moveintogroup d ; dispatch setfloating address:${addr} ; dispatch resizewindowpixel exact ${SIXTEEN_NINE_W} ${SIXTEEN_NINE_H},address:${addr} ; dispatch movewindowpixel exact ${SIXTEEN_NINE_LEFT} ${SIXTEEN_NINE_TOP},address:${addr} ; ${show}"
	fi
}
