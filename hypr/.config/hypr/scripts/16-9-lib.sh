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

	local mon_x mon_y mon_w mon_h left right top bottom
	mon_x=$(jq -r '.x' <<<"$mon_json")
	mon_y=$(jq -r '.y' <<<"$mon_json")
	# Monitor modes use physical pixels; window dispatches use logical pixels.
	# Rotations with an odd transform exchange the logical width and height.
	read -r mon_w mon_h < <(jq -r '
		(.scale // 1) as $scale |
		if ((.transform // 0) % 2 == 1) then
			[.height / $scale, .width / $scale]
		else
			[.width / $scale, .height / $scale]
		end | map(floor) | @tsv' <<<"$mon_json")
	# Reserved edges are left, top, right, bottom. The current bar reserves
	# 56 logical pixels on the left, not at the top.
	left=$(jq -r '.reserved[0]' <<<"$mon_json")
	top=$(jq -r '.reserved[1]' <<<"$mon_json")
	right=$(jq -r '.reserved[2]' <<<"$mon_json")
	bottom=$(jq -r '.reserved[3]' <<<"$mon_json")

	# Fill the usable desktop with equal 5-logical-pixel margins.
	# Margins start inside any reserved bar area. Do not force 16:9:
	# that adds side margins on a 16:9 display when a bar reserves height.
	local margin=5
	local work_left work_top work_w work_h
	work_left=$((mon_x + left + margin))
	work_top=$((mon_y + top + margin))
	work_w=$((mon_w - left - right - 2 * margin))
	work_h=$((mon_h - top - bottom - 2 * margin))

	((work_w > 0 && work_h > 0)) || return 1
	SIXTEEN_NINE_W=$work_w
	SIXTEEN_NINE_H=$work_h
	SIXTEEN_NINE_LEFT=$work_left
	SIXTEEN_NINE_TOP=$work_top
	# Hyprland windowrule move/size use monitor-local coordinates.
	SIXTEEN_NINE_MOVE_X=$((SIXTEEN_NINE_LEFT - mon_x))
	SIXTEEN_NINE_MOVE_Y=$((SIXTEEN_NINE_TOP - mon_y))
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
	# hl.dsp.window.float action=set toggles — only call when not already floating.
	local is_float
	is_float=$(hyprctl clients -j 2>/dev/null | jq -r --arg a "$addr" '.[] | select(.address == $a) | .floating')
	if [[ "$is_float" != "true" ]]; then
		hyprctl dispatch "hl.dsp.window.float({ action = \"set\", window = \"address:$addr\" })"
	fi
	hyprctl dispatch "hl.dsp.window.resize({ x = $SIXTEEN_NINE_W, y = $SIXTEEN_NINE_H, relative = false, window = \"address:$addr\" })"
	hyprctl dispatch "hl.dsp.window.move({ x = $SIXTEEN_NINE_LEFT, y = $SIXTEEN_NINE_TOP, relative = false, window = \"address:$addr\" })"
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

	local is_float ws_id mon_id grouped_len current_w current_h
	is_float=$(jq -r '.floating' <<<"$win_json")
	ws_id=$(jq -r '.workspace.id' <<<"$win_json")
	mon_id=$(jq -r '.monitor' <<<"$win_json")
	grouped_len=$(jq -r '.grouped | length' <<<"$win_json")
	current_w=$(jq -r '.size[0]' <<<"$win_json")
	current_h=$(jq -r '.size[1]' <<<"$win_json")

	# Workspace 2: monocle only unless 16:9 was toggled manually.
	if [[ "$ws_id" == "2" ]]; then
		local mode
		mode=$(head -1 "$MODE_FLAG" 2>/dev/null)
		[[ "$mode" == "all" || "$mode" == "2" ]] || return 0
	fi

	sixteen_nine_enable_workspace "$ws_id"
	sixteen_nine_geometry "$mon_id" || return 1

	# Re-selecting an app already in the correct mode must not recreate its
	# single-window group or shift it by a rounding pixel.
	if [[ "$is_float" == "true" && "$current_w" == "$SIXTEEN_NINE_W" && "$current_h" == "$SIXTEEN_NINE_H" ]]; then
		return 0
	fi

	# Already grouped: float and size the whole group. This also handles windows
	# moved by workspace rules before the open-window listener finishes.
	if [[ "$grouped_len" -gt 0 ]]; then
		sixteen_nine_float_resize "$addr" >/dev/null 2>&1 || true
		return 0
	fi

	local group_addr
	group_addr=$(hyprctl clients -j 2>/dev/null \
		| jq -r --argjson ws "$ws_id" '[.[] | select(.workspace.id == $ws and (.grouped | length) > 0)] | .[0].address // empty')

	if [[ -z "$group_addr" ]]; then
		hyprctl dispatch "hl.dsp.window.set_prop({ prop = \"opacity\", value = \"0 override\", window = \"address:$addr\" })" >/dev/null 2>&1 || true
		hyprctl dispatch "hl.dsp.window.float({ action = \"unset\", window = \"address:$addr\" })" >/dev/null 2>&1 || true
		hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null 2>&1 || true
		hyprctl dispatch "hl.dsp.group.toggle({ window = \"address:$addr\" })" >/dev/null 2>&1 || true
	else
		hyprctl dispatch "hl.dsp.window.set_prop({ prop = \"opacity\", value = \"0 override\", window = \"address:$addr\" })" >/dev/null 2>&1 || true
		hyprctl dispatch "hl.dsp.window.float({ action = \"unset\", window = \"address:$group_addr\" })" >/dev/null 2>&1 || true
		hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null 2>&1 || true
		for direction in left right up down; do
			hyprctl dispatch "hl.dsp.window.move({ into_group = \"$direction\", window = \"address:$addr\" })" >/dev/null 2>&1 || true
		done
	fi

	sixteen_nine_float_resize "$addr" >/dev/null 2>&1 || true
	hyprctl dispatch "hl.dsp.window.set_prop({ prop = \"opacity\", value = \"1 override\", window = \"address:$addr\" })" >/dev/null 2>&1 || true
}
